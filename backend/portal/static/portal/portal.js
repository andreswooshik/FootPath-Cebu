(() => {
  const sidebar = document.querySelector('[data-mobile-sidebar]');
  const overlay = document.querySelector('[data-mobile-menu-overlay]');
  const openButton = document.querySelector('[data-mobile-menu-toggle]');
  const closeButton = document.querySelector('[data-mobile-menu-close]');

  if (!sidebar || !overlay || !openButton || !closeButton) return;

  const setOpen = (open) => {
    sidebar.classList.toggle('-translate-x-full', !open);
    overlay.classList.toggle('hidden', !open);
    openButton.setAttribute('aria-expanded', String(open));
    document.body.classList.toggle('overflow-hidden', open);

    if (open) {
      closeButton.focus();
    } else if (window.innerWidth < 1024) {
      openButton.focus();
    }
  };

  openButton.addEventListener('click', () => setOpen(true));
  closeButton.addEventListener('click', () => setOpen(false));
  overlay.addEventListener('click', () => setOpen(false));

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && openButton.getAttribute('aria-expanded') === 'true') {
      setOpen(false);
    }
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth >= 1024) {
      overlay.classList.add('hidden');
      openButton.setAttribute('aria-expanded', 'false');
      document.body.classList.remove('overflow-hidden');
    } else {
      sidebar.classList.add('-translate-x-full');
    }
  });
})();

(() => {
  document.querySelectorAll('[data-password-toggle]').forEach((button) => {
    const input = button.closest('.password-control')?.querySelector('input');
    if (!input) return;

    button.addEventListener('click', () => {
      const revealing = input.type === 'password';
      input.type = revealing ? 'text' : 'password';
      button.textContent = revealing ? 'Hide' : 'Show';
      button.setAttribute('aria-label', revealing ? 'Hide password' : 'Show password');
      input.focus();
    });
  });
})();

(() => {
  document.querySelectorAll('form[data-submit-once]').forEach((form) => {
    form.addEventListener('submit', (event) => {
      const button = event.submitter || form.querySelector('button[type="submit"]');
      if (!button) return;
      if (button.disabled) {
        event.preventDefault();
        return;
      }
      button.disabled = true;
      button.setAttribute('aria-busy', 'true');
      button.textContent = button.dataset.loadingLabel || 'Please wait…';
    });
  });
})();

(() => {
  const affiliation = document.getElementById('id_is_school_affiliated');
  const schoolName = document.querySelector('[data-school-name-field]');
  if (!affiliation || !schoolName) return;

  const updateSchoolField = () => {
    schoolName.hidden = !affiliation.checked;
    const input = schoolName.querySelector('input');
    if (input) input.disabled = !affiliation.checked;
  };

  affiliation.addEventListener('change', updateSchoolField);
  updateSchoolField();
})();

(() => {
  const root = document.querySelector('[data-account-tabs]');
  if (!root) return;

  const tabs = [...root.querySelectorAll('[data-account-tab]')];
  const panels = [...root.querySelectorAll('[data-account-panel]')];
  const validTypes = new Set(tabs.map((tab) => tab.dataset.accountTab));

  const activate = (type, updateHash = false) => {
    if (!validTypes.has(type)) return;
    tabs.forEach((tab) => {
      const selected = tab.dataset.accountTab === type;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
    });
    panels.forEach((panel) => {
      panel.hidden = panel.dataset.accountPanel !== type;
    });
    if (updateHash) history.replaceState(null, '', `#${type}`);
  };

  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activate(tab.dataset.accountTab, true));
    tab.addEventListener('keydown', (event) => {
      if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
      event.preventDefault();
      const direction = event.key === 'ArrowRight' ? 1 : -1;
      const next = tabs[(index + direction + tabs.length) % tabs.length];
      activate(next.dataset.accountTab, true);
      next.focus();
    });
  });

  const hashType = window.location.hash.slice(1);
  activate(validTypes.has(hashType) ? hashType : root.dataset.defaultAccountTab);
})();

(() => {
  document.querySelectorAll('[data-copy-target]').forEach((button) => {
    button.addEventListener('click', async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      if (!target) return;
      const originalLabel = button.dataset.copyLabel || button.textContent;
      try {
        await navigator.clipboard.writeText(target.textContent.trim());
        button.textContent = 'Copied';
        button.setAttribute('aria-live', 'polite');
      } catch (_) {
        const range = document.createRange();
        range.selectNodeContents(target);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        button.textContent = 'Select and copy';
      }
      window.setTimeout(() => {
        button.textContent = originalLabel;
      }, 2500);
    });
  });
})();

(() => {
  const tables = new Map();

  const getTableState = (targetId) => {
    if (!tables.has(targetId)) {
      tables.set(targetId, { query: '', filters: new Map() });
    }
    return tables.get(targetId);
  };

  const applyFilters = (targetId) => {
    const table = document.getElementById(targetId);
    if (!table) return;

    const state = getTableState(targetId);
    const rows = table.querySelectorAll('[data-filter-row]');
    let visible = 0;

    rows.forEach((row) => {
      const searchText = (row.dataset.search || row.textContent).toLowerCase();
      const matchesSearch = searchText.includes(state.query);
      const matchesFilters = [...state.filters.entries()].every(
        ([key, value]) => !value || row.dataset[key] === value,
      );
      const show = matchesSearch && matchesFilters;
      row.hidden = !show;
      if (show) visible += 1;
    });

    const emptyState = document.querySelector(`[data-filter-empty="${targetId}"]`);
    if (emptyState) emptyState.hidden = visible !== 0;
  };

  document.querySelectorAll('[data-table-search]').forEach((input) => {
    const targetId = input.dataset.tableSearch;
    input.addEventListener('input', () => {
      getTableState(targetId).query = input.value.trim().toLowerCase();
      applyFilters(targetId);
    });
  });

  document.querySelectorAll('[data-table-filter]').forEach((select) => {
    const targetId = select.dataset.tableFilter;
    const key = select.dataset.filterKey;
    select.addEventListener('change', () => {
      getTableState(targetId).filters.set(key, select.value);
      applyFilters(targetId);
    });
  });
})();

(() => {
  const dialog = document.querySelector('[data-confirm-dialog]');
  if (!dialog) return;

  const title = dialog.querySelector('[data-confirm-title]');
  const message = dialog.querySelector('[data-confirm-message]');
  const confirmButton = dialog.querySelector('[data-confirm-button]');
  let pendingForm = null;

  document.querySelectorAll('form[data-confirm]').forEach((form) => {
    form.addEventListener('submit', (event) => {
      event.preventDefault();
      pendingForm = form;
      title.textContent = form.dataset.confirmTitle || 'Confirm action';
      message.textContent = form.dataset.confirmMessage || 'This action cannot be undone.';
      confirmButton.textContent = form.dataset.confirmAction || 'Confirm';

      if (typeof dialog.showModal === 'function') {
        dialog.showModal();
      } else if (window.confirm(message.textContent)) {
        form.submit();
      }
    });
  });

  dialog.addEventListener('close', () => {
    if (dialog.returnValue === 'confirm' && pendingForm) {
      const form = pendingForm;
      pendingForm = null;
      form.submit();
      return;
    }
    pendingForm = null;
  });
})();
