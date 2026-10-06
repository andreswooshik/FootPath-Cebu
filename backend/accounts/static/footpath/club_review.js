/* Club review reuses the authenticated Django change form and its messages.
   No status is changed until confirmation; returned HTML supplies the true state. */
(function () {
  function initialise() {
    var fallback = document.querySelector('[data-review-fallback]');
    if (fallback) {
      var submitting = false;
      fallback.addEventListener('submit', function (event) {
        if (submitting) {
          event.preventDefault();
          return;
        }
        submitting = true;
        var button = fallback.querySelector('button[type="submit"]');
        button.disabled = true;
        button.textContent = button.dataset.loadingLabel;
        fallback.setAttribute('aria-busy', 'true');
      });
      return;
    }

    var panel = document.querySelector('[data-club-review]');
    var dialog = document.querySelector('[data-review-dialog]');
    // The server provides a confirmation page when the modal/fetch is unavailable.
    if (!panel || !dialog || !dialog.showModal || !window.fetch) return;

    var form = panel.closest('form');
    var confirm = dialog.querySelector('[data-review-confirm]');
    var cancel = dialog.querySelector('[data-review-cancel]');
    var title = document.getElementById('club-review-dialog-title');
    var message = document.getElementById('club-review-dialog-message');
    var notifications = document.getElementById('club-review-messages');
    var actions = panel.querySelector('.fp-application-review__actions');
    var decision = null;
    var processing = false;
    var state = 'PENDING';

    function notify(text, level) {
      var alert = document.createElement('div');
      alert.className = 'alert alert-' + level;
      alert.setAttribute('role', 'alert');
      alert.textContent = text;
      notifications.replaceChildren(alert);
    }

    function setProcessing(value) {
      processing = value;
      form.setAttribute('aria-busy', String(value));
      dialog.setAttribute('aria-busy', String(value));
      confirm.disabled = value;
      cancel.disabled = value;
      actions.querySelectorAll('button').forEach(function (button) {
        button.disabled = value || state !== 'PENDING';
      });
      confirm.textContent = value
        ? (decision === '_approve_application' ? 'Approving...' : 'Rejecting...')
        : (decision === '_approve_application' ? 'Approve' : 'Reject');
    }

    function refreshFromHTML(html, showMessages) {
      var page = new DOMParser().parseFromString(html, 'text/html');
      var marker = page.getElementById('club-registration-state');
      if (!marker) throw new Error('The application could not be refreshed. Check your session and try again.');
      state = marker.dataset.state;
      document.getElementById('club-registration-state').dataset.state = state;
      if (state !== 'PENDING') {
        actions.hidden = true;
        var status = panel.querySelector('.fp-application-review__status');
        status.dataset.state = state;
        status.textContent = { APPROVED: 'Approved', NOT_APPROVED: 'Not approved', INCOMPLETE: 'Incomplete' }[state] || state;
        panel.querySelector('p').textContent = 'This application is no longer pending review.';
      }
      if (showMessages) {
        var messages = page.getElementById('club-review-messages');
        if (messages) notifications.replaceChildren.apply(notifications, Array.from(messages.childNodes));
      }
    }

    form.addEventListener('submit', function (event) {
      var button = event.submitter;
      // Block implicit submissions and repeat submissions on the review form.
      event.preventDefault();
      if (processing || state !== 'PENDING' || !button ||
          ['_approve_application', '_not_approve_application'].indexOf(button.name) === -1) return;
      decision = button.name;
      var approving = decision === '_approve_application';
      title.textContent = approving ? 'Approve Club Application?' : 'Reject Club Application?';
      message.textContent = 'Are you sure you want to ' + (approving ? 'approve' : 'reject') +
        ' "' + panel.dataset.clubName + '"?\n\n' + (approving
          ? 'Approving this application will allow the club and its approved Coordinator to access FootPath.'
          : "The club's application will be marked as not approved. The Coordinator will remain unable to sign in.");
      confirm.className = 'btn ' + (approving ? 'btn-success' : 'btn-danger');
      setProcessing(false);
      dialog.showModal();
      cancel.focus();
    });

    cancel.addEventListener('click', function () {
      if (!processing) dialog.close();
    });
    dialog.addEventListener('cancel', function (event) {
      if (processing) event.preventDefault();
    });
    dialog.addEventListener('close', function () {
      if (!processing) decision = null;
    });

    confirm.addEventListener('click', async function () {
      if (processing || !decision || state !== 'PENDING' || !dialog.open) return;
      var body = new FormData(form);
      body.set(decision, '1');
      body.set('_confirm_application', '1');
      setProcessing(true); // Synchronous guard prevents rapid repeated clicks.
      try {
        var response = await window.fetch(form.action || window.location.href, {
          method: 'POST', credentials: 'same-origin', body: body
        });
        if (!response.ok) throw new Error('The decision could not be saved. Check your session and try again.');
        refreshFromHTML(await response.text(), true);
      } catch (error) {
        // A lost response may follow a committed decision. Read the actual state
        // before allowing a retry, rather than claiming success or assuming Pending.
        try {
          var refreshed = await window.fetch(form.action || window.location.href, {
            credentials: 'same-origin', cache: 'no-store'
          });
          if (!refreshed.ok) throw new Error('Refresh failed');
          refreshFromHTML(await refreshed.text(), false);
          notify('The decision response could not be confirmed. Current application status: ' +
            ({ APPROVED: 'Approved', NOT_APPROVED: 'Not approved', PENDING: 'Pending' }[state] || state) +
            '. Review the status before trying again.', 'danger');
        } catch (refreshError) {
          // Keep actions disabled until the administrator can reload fresh state.
          state = 'UNKNOWN';
          notify('The decision could not be confirmed and the current status is unavailable. Reopen the application before trying again.', 'danger');
        }
      } finally {
        setProcessing(false);
        dialog.close();
        decision = null;
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialise);
  } else {
    initialise();
  }
})();
