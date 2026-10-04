/* ---------------------------------------------------------------------------
 * ux.js -- quality-of-life on the generate page.
 *
 * Three small things that make the page work for the way researchers
 * actually use it:
 *
 *   1. URL state.  A chosen element and physics become part of the URL,
 *      so a reader can bookmark a selection or send it to a colleague.
 *      Every state the page accepts through the UI is accepted through
 *      the URL; anything the URL cannot express is not state.
 *
 *   2. Keyboard shortcuts.  "/" focuses the search box, Escape clears it,
 *      Enter selects the first visible element.  These are the bindings
 *      people already know from other tools; inventing new ones would be
 *      worse than having none.
 *
 *   3. A "Copy command" button.  The site's whole purpose is to make the
 *      file easy to obtain; the second-most-common thing a reader wants
 *      after the file is the command that would produce it locally, to
 *      put in a script.  That command is on the page already, in prose.
 *      A button that puts it on the clipboard turns prose into a tool.
 *
 * Nothing here modifies main.js.  Everything is a side-effect on top of
 * the page as main.js renders it, hooked on DOM changes so it stays
 * correct when the page updates.
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  if (window.__pfUxInstalled) return;
  window.__pfUxInstalled = true;

  // -------------------------------------------------------------------------
  // 1. URL state
  // -------------------------------------------------------------------------

  // The names are short and stable so a bookmarked URL survives a redesign
  // of the query string.  e = element, xc = functional, f = family,
  // r = relativity, p = profile.
  const PARAM = { element: 'e', xc: 'xc', family: 'f', relativity: 'r', profile: 'p' };

  function readUrl() {
    const q = new URLSearchParams(location.search);
    const out = {};
    for (const [key, short] of Object.entries(PARAM)) {
      const v = q.get(short);
      if (v) out[key] = v;
    }
    return out;
  }

  function writeUrl() {
    if (typeof state === 'undefined' || !state.element) return;
    const q = new URLSearchParams();
    q.set('e', state.element.symbol);
    const w = typeof want === 'function' ? want() : {};
    if (w.xc)     q.set('xc', w.xc);
    if (w.family) q.set('f',  w.family);
    if (w.rel)    q.set('r',  w.rel);
    if (state.pickedProfile) q.set('p', state.pickedProfile);
    const url = location.pathname + '?' + q.toString();
    history.replaceState(null, '', url);
  }

  // Apply the URL after main.js has rendered for the first time.
  function applyUrl() {
    const u = readUrl();
    if (!Object.keys(u).length) return;
    if (typeof state === 'undefined' || typeof drawTable !== 'function') return;

    // Wait until the element list has arrived, so we can find the element
    // by symbol rather than guess at timing.
    const tryApply = () => {
      if (!state.native.length) { setTimeout(tryApply, 100); return; }
      const cell = document.querySelector(`.el[data-symbol="${u.element}"]`);
      if (!cell) return;
      cell.click();
      // Physics choices are applied after the click because choose() resets
      // the dropdowns to the element's available options.
      setTimeout(() => {
        if (u.xc) {
          const sel = document.getElementById('xc');
          if (sel && [...sel.options].some(o => o.value === u.xc)) sel.value = u.xc;
        }
        if (u.family) {
          const sel = document.getElementById('family');
          if (sel && [...sel.options].some(o => o.value === u.family)) sel.value = u.family;
        }
        if (u.relativity) {
          const sel = document.getElementById('rel');
          if (sel && [...sel.options].some(o => o.value === u.relativity)) sel.value = u.relativity;
        }
        if (u.profile) state.pickedProfile = u.profile;
        if (typeof refresh === 'function') refresh();
      }, 100);
    };
    tryApply();
  }

  // -------------------------------------------------------------------------
  // 2. Keyboard shortcuts
  // -------------------------------------------------------------------------

  document.addEventListener('keydown', (ev) => {
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
          first.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  // 3. Copy command
  // -------------------------------------------------------------------------

  function buildCommand() {
    if (typeof state === 'undefined' || !state.element) return null;
    const w = typeof want === 'function' ? want() : {};
    if (!state.match) return null;
    const profile = (state.match && state.match.profile) || state.pickedProfile || 'pseudoforge-auto';
    const parts = [
      'pseudoforge generate',
      '-e', state.element.symbol,
      '-t', w.family || 'nc',
      '-x', w.xc || 'pbe',
      '-r', w.rel || 'scalar',
      '-p', profile,
      '-o', './out',
    ];
    return parts.join(' ');
  }

  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); return true; }
    catch (e) {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed'; ta.style.left = '-9999px';
      document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy'); } catch (e2) {}
      document.body.removeChild(ta);
      return true;
    }
  }

  function ensureCopyButton() {
    const actions = document.querySelector('#summary-card .actions');
    if (!actions || document.getElementById('btn-copy-cmd')) return;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'btn';
    btn.id = 'btn-copy-cmd';
    btn.textContent = 'Copy CLI command';
    btn.title = 'Copy the equivalent pseudoforge generate command';
    btn.addEventListener('click', async () => {
      const cmd = buildCommand();
      if (!cmd) { btn.textContent = 'Nothing to copy'; setTimeout(() => btn.textContent = 'Copy CLI command', 1200); return; }
      const ok = await copyText(cmd);
      const orig = btn.textContent;
      btn.textContent = ok ? 'Copied' : 'Failed';
      setTimeout(() => btn.textContent = orig, 1200);
    });
    actions.appendChild(btn);
  }

  // -------------------------------------------------------------------------
  // Boot
  // -------------------------------------------------------------------------

  document.addEventListener('DOMContentLoaded', () => {
    // Give main.js a moment to define state and draw the initial table.
    setTimeout(() => {
      applyUrl();
      ensureCopyButton();

      // Watch for state changes and update the URL.  Debounced so a rapid
      // series of choices does not spam history.replaceState.
      let t = null;
      const observer = new MutationObserver(() => {
        clearTimeout(t);
        t = setTimeout(writeUrl, 250);
      });
      const summary = document.getElementById('summary');
      if (summary) observer.observe(summary, { childList: true, subtree: true, characterData: true });

      // Also update on physics dropdown changes.
      ['xc', 'family', 'rel'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.addEventListener('change', () => setTimeout(writeUrl, 50));
      });
    }, 200);
  });
})();
