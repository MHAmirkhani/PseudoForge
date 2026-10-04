/* ---------------------------------------------------------------------------
 * cite.js -- a "Cite" button next to every download row.
 *
 * The whole project exists to make the provenance of a pseudopotential
 * answerable six months later.  The download page is where a reader ends
 * up with a file, so it is where they should also end up with the citation
 * for that file, without having to look it up somewhere else.
 *
 * The BibTeX entry this copies is deliberately honest about what it is:
 * a machine-generated reference to a specific file in a specific store,
 * naming the engine that produced it and pointing at the PseudoForge docs
 * for the human-meaningful citations of the underlying methods.  It does
 * not claim to be the citation of the engine's paper -- that belongs to
 * the engine's authors, and PseudoForge writes those into the store's
 * provenance files where they belong.
 *
 * Delegation
 * ----------
 * The table body is re-rendered every time the filter or page changes, so
 * listeners attached to individual buttons would be lost.  One delegated
 * handler on document catches every Cite button, however many times the
 * table is rebuilt.
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  if (window.__pfCiteInstalled) return;
  window.__pfCiteInstalled = true;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }

  function bibtexFor(row) {
    // A stable, filesystem-safe key.
    const id = [
      row.element, row.xc, row.family, row.relativity, row.profile || row.engine
    ].filter(Boolean).join('_').replace(/[^A-Za-z0-9_]/g, '');

    // The fields a reader can see on the page are the ones we put in the
    // entry.  No guessing.
    const fields = [
      ['title',  `${row.element} ${String(row.xc).toUpperCase()} ${row.family} ` +
                 `${row.relativity} pseudopotential` +
                 (row.profile ? ` from ${row.profile}` : '')],
      ['author', '{PseudoForge}'],
      ['year',   String(new Date().getFullYear())],
      ['howpublished', `PseudoForge native store, ${row.format}`],
      ['note',   `Generated with ${row.engine}. ` +
                 `For the engine's own citation see ` +
                 `https://pseudo.amirkhani.me/docs/reference/engines/`],
    ];

    const body = fields.map(([k, v]) => `  ${k} = {${v}}`).join(',\n');
    return `@misc{pseudoforge_${id},\n${body}\n}`;
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      // Fallback for browsers that refuse clipboard without user gesture.
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); }
      catch (e2) { document.body.removeChild(ta); return false; }
      document.body.removeChild(ta);
      return true;
    }
  }

  // Add a Cite button to every row that has a Download button.  A
  // MutationObserver on #list catches rows whether they were rendered
  // before or after this script runs.
  function decorateRow(tr) {
    if (tr.dataset.pfCite) return;
    const dl = tr.querySelector('a.btn');
    if (!dl) return;
    tr.dataset.pfCite = '1';

    const cite = document.createElement('button');
    cite.type = 'button';
    cite.className = 'btn cite-btn';
    cite.textContent = 'Cite';
    cite.title = 'Copy a BibTeX entry for this file';

    dl.parentElement.appendChild(document.createTextNode(' '));
    dl.parentElement.appendChild(cite);
  }

  function decorateAll() {
    document.querySelectorAll('#list table.files tbody tr').forEach(decorateRow);
  }

  document.addEventListener('DOMContentLoaded', () => {
    decorateAll();
    const list = document.getElementById('list');
    if (!list) return;
    new MutationObserver(decorateAll).observe(list, { childList: true, subtree: true });
  });

  // Delegated click handler.
  document.addEventListener('click', async (ev) => {
    const btn = ev.target.closest('.cite-btn');
    if (!btn) return;
    ev.preventDefault();

    const tr = btn.closest('tr');
    if (!tr) return;

    // Reconstruct the row from the cells.  The order matches the table
    // headings on the download page: Element, Functional, Family,
    // Relativity, Engine, Format, Size, (Provenance was removed).
    const tds = tr.querySelectorAll('td');
    const row = {
      element:    tds[0]?.textContent.trim(),
      xc:         tds[1]?.textContent.trim(),
      family:     tds[2]?.textContent.trim(),
      relativity: tds[3]?.textContent.trim(),
      engine:     tds[4]?.textContent.trim(),
      format:     tds[5]?.textContent.trim(),
    };

    const ok = await copyText(bibtexFor(row));
    const original = btn.textContent;
    btn.textContent = ok ? 'Copied' : 'Failed';
    btn.disabled = true;
    setTimeout(() => { btn.textContent = original; btn.disabled = false; }, 1200);
  });
})();
