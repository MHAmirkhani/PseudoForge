/* Keyboard shortcuts for the periodic table. */
'use strict';

  document.addEventListener('keydown', (ev) => {
    if (ev.target.isContentEditable) return;
    const tag = (ev.target.tagName || '').toLowerCase();
    const inField = tag === 'input' || tag === 'textarea' || tag === 'select';
    if (ev.metaKey || ev.ctrlKey || ev.altKey) return;

    if (ev.key === '/' && !inField) {
      const inp = document.getElementById('ptable-q');
      if (inp) { ev.preventDefault(); inp.focus(); inp.select(); }
    }
    if (ev.key === 'Escape') {
      const inp = document.getElementById('ptable-q');
      if (inp && document.activeElement === inp) {
        inp.value = '';
        if (typeof state !== 'undefined') state.filter.q = '';
        inp.dispatchEvent(new Event('input', { bubbles: true }));
        inp.blur();
      }
    }
    if (ev.key === 'Enter' && inField) {
      const inp = document.getElementById('ptable-q');
      if (inp && document.activeElement === inp) {
        const first = document.querySelector('.el:not(.filtered-out)');
        if (first) {
          ev.preventDefault();
          first.click();
          first.scrollIntoView({ block: 'nearest', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
        }
      }
    }
  });
