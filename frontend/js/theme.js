/* ---------------------------------------------------------------------------
 * theme.js -- colour theme for every page on the site.
 *
 * Light is the default.  That is a deliberate choice, not a fallback: most
 * of the material this site presents -- element blocks, provenance tables,
 * the periodic table itself -- was designed for print and reads better on
 * paper-white than on a dark surface.  A reader who prefers dark can ask
 * for it once and the choice is remembered.
 *
 * The inline boot snippet that every page carries in its <head> uses the
 * same default and the same key.  If those two ever disagree the site will
 * flash the wrong theme on load.
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  var KEY = 'pf-theme';
  var DEFAULT = 'light';

  function current() {
    return document.documentElement.dataset.theme === 'dark' ? 'dark' : 'light';
  }

  function apply(theme, animate) {
    document.documentElement.dataset.theme = theme;
    if (animate) {
      document.documentElement.classList.add('theme-anim');
      setTimeout(function () {
        document.documentElement.classList.remove('theme-anim');
      }, 250);
    }
    var btn = document.getElementById('theme-toggle');
    if (btn) {
      // Label describes the state the reader will move to, not the current one.
      btn.setAttribute('aria-label',
        theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
      btn.title = theme === 'dark' ? 'Light' : 'Dark';
    }
  }

  function init() {
    var saved = null;
    try { saved = localStorage.getItem(KEY); } catch (e) { /* disabled */ }
    apply(saved === 'dark' || saved === 'light' ? saved : DEFAULT, false);

    var btn = document.getElementById('theme-toggle');
    if (btn && !btn.dataset.wired) {
      btn.dataset.wired = '1';
      btn.addEventListener('click', function () {
        var next = current() === 'dark' ? 'light' : 'dark';
        apply(next, true);
        try { localStorage.setItem(KEY, next); } catch (e) { /* ignore */ }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
