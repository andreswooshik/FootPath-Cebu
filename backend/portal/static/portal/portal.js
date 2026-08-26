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
