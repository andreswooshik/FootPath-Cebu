/* FootPath Cebu — admin control-bar enhancer.
   Loaded via JAZZMIN_SETTINGS['custom_js'] on every admin page.

   Two jobs, both purely cosmetic and fully defensive (any failure is caught and
   the stock layout is left intact):

   1. Rename the bulk-action dropdown's empty "---------" option to "Bulk Actions".
   2. Lift the bulk-action toolbar (.actions) out of the changelist <form> and into
      the top control bar's right-hand group, so filters/search sit left and the
      bulk selector + Go + Add User sit together on the right.

   The relocated <select>/<button> keep working because we tag them with
   form="changelist-form" (HTML5 form association): a control can submit to a form
   it no longer lives inside, so bulk actions still post with the row checkboxes. */

(function () {
  function ready(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  function enhance() {
    try {
      var actionSelect = document.querySelector('select[name="action"]');
      if (actionSelect) {
        // 1) Friendly placeholder text (native option + select2's rendered label).
        Array.prototype.forEach.call(actionSelect.options, function (opt) {
          if (opt.value === '' && /^-+$/.test(opt.textContent.trim())) {
            opt.textContent = 'Bulk Actions';
          }
        });
        var wrap = actionSelect.closest('.actions');
        if (wrap && actionSelect.value === '') {
          var rendered = wrap.querySelector('.select2-selection__rendered');
          if (rendered) {
            rendered.textContent = 'Bulk Actions';
            rendered.setAttribute('title', 'Bulk Actions');
          }
        }
      }

      // 1b) Strip the redundant dashed "---------" placeholder from filter
      //     dropdowns (the title option already acts as the placeholder). select2
      //     re-reads options when the panel next opens, so this cleans the list.
      document.querySelectorAll('select.search-filter').forEach(function (sel) {
        Array.prototype.forEach.call(sel.querySelectorAll('option[value=""]'), function (opt) {
          if (/^-+$/.test(opt.textContent.trim())) {
            opt.remove();
          }
        });
      });

      // NOTE: we intentionally DON'T relocate the bulk-actions toolbar into the
      // top control bar anymore. Keeping the three concerns separated reads more
      // cleanly: filters/search + Add user live in the control bar, while the
      // bulk-actions (delete) toolbar stays in its natural strip above the table.
    } catch (e) {
      if (window.console) {
        console.warn('[footpath] control-bar enhance skipped:', e);
      }
    }
  }

  // Defer a tick so Jazzmin's select2 initialisation has already run.
  ready(function () {
    window.setTimeout(enhance, 0);
  });
})();

/* Live Coordinator-password feedback on the Add/Edit Club form. The quick
   client checks update immediately; a debounced staff-only admin endpoint then
   applies Django's exact configured validators (including its common-password
   list and similarity algorithm). */
(function () {
  function ready(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }

  function initialiseCoordinatorPasswordFeedback() {
    var password = document.getElementById('id_coordinator_password1');
    var confirmation = document.getElementById('id_coordinator_password2');
    var requirements = document.getElementById('coordinator-password-requirements');
    if (!password || !confirmation || !requirements) {
      return;
    }

    var email = document.getElementById('id_coordinator_email');
    var name = document.getElementById('id_coordinator_name');
    var matchMessage = document.getElementById('coordinator-password-match');
    var timer = null;
    var requestNumber = 0;
    var commonFallback = [
      'password', 'password1', 'password123', '12345678', '123456789',
      'qwerty123', 'admin123', 'letmein', 'football', 'iloveyou'
    ];

    function setRule(ruleName, met) {
      var item = requirements.querySelector('[data-password-rule="' + ruleName + '"]');
      if (!item) {
        return;
      }
      var nextClass = met ? 'is-met' : 'is-unmet';
      if (item.classList.contains(nextClass)) {
        return;
      }
      item.classList.remove('is-met', 'is-unmet', 'is-changing');
      item.classList.add(nextClass);
      // Restart the small state-change animation even after rapid typing.
      void item.offsetWidth;
      item.classList.add('is-changing');
      window.setTimeout(function () {
        item.classList.remove('is-changing');
      }, 280);
    }

    function normalise(value) {
      return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    }

    function fallbackSimilarity(value) {
      var candidate = normalise(value);
      var personalValues = [
        email ? email.value.split('@')[0] : '',
        name ? name.value : ''
      ];
      var tokens = [];
      personalValues.forEach(function (personalValue) {
        String(personalValue).split(/\s+/).forEach(function (token) {
          token = normalise(token);
          if (token.length >= 3) {
            tokens.push(token);
          }
        });
      });
      return candidate.length > 0 && !tokens.some(function (token) {
        return candidate.indexOf(token) !== -1 || token.indexOf(candidate) !== -1;
      });
    }

    function updateConfirmation() {
      var first = password.value;
      var second = confirmation.value;
      confirmation.classList.remove(
        'fp-password-input-match',
        'fp-password-input-mismatch'
      );
      matchMessage.classList.remove('is-met', 'is-unmet', 'is-pending');
      if (!second) {
        matchMessage.textContent = 'Enter the same password again.';
        matchMessage.classList.add('is-pending');
        confirmation.removeAttribute('aria-invalid');
      } else if (first && first === second) {
        matchMessage.textContent = 'Passwords match.';
        matchMessage.classList.add('is-met');
        confirmation.classList.add('fp-password-input-match');
        confirmation.setAttribute('aria-invalid', 'false');
      } else {
        matchMessage.textContent = 'Passwords do not match.';
        matchMessage.classList.add('is-unmet');
        confirmation.classList.add('fp-password-input-mismatch');
        confirmation.setAttribute('aria-invalid', 'true');
      }
    }

    function updateImmediateRules() {
      var value = password.value;
      var lower = value.toLowerCase();
      setRule('minimum_length', value.length >= 8);
      setRule('numeric', value.length > 0 && !/^\d+$/.test(value));
      setRule('common', value.length > 0 && commonFallback.indexOf(lower) === -1);
      setRule('similarity', fallbackSimilarity(value));
      updateConfirmation();
    }

    function requestExactRules() {
      var checkUrl = password.getAttribute('data-password-check-url');
      var csrf = document.querySelector('input[name="csrfmiddlewaretoken"]');
      if (!checkUrl || !csrf || !password.value) {
        return;
      }
      requestNumber += 1;
      var thisRequest = requestNumber;
      window.fetch(checkUrl, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRFToken': csrf.value
        },
        body: JSON.stringify({
          password: password.value,
          email: email ? email.value : '',
          name: name ? name.value : ''
        })
      }).then(function (response) {
        if (!response.ok) {
          throw new Error('Password validation request failed.');
        }
        return response.json();
      }).then(function (data) {
        if (thisRequest !== requestNumber || !data.rules) {
          return;
        }
        Object.keys(data.rules).forEach(function (ruleName) {
          setRule(ruleName, Boolean(data.rules[ruleName]));
        });
      }).catch(function () {
        // The immediate checks remain usable if the network request fails.
      });
    }

    function scheduleUpdate() {
      updateImmediateRules();
      window.clearTimeout(timer);
      timer = window.setTimeout(requestExactRules, 180);
    }

    password.addEventListener('input', scheduleUpdate);
    confirmation.addEventListener('input', updateConfirmation);
    if (email) {
      email.addEventListener('input', scheduleUpdate);
    }
    if (name) {
      name.addEventListener('input', scheduleUpdate);
    }
    updateImmediateRules();
  }

  ready(initialiseCoordinatorPasswordFeedback);
})();
