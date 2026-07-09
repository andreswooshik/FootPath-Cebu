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
