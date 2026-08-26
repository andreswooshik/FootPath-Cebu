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
