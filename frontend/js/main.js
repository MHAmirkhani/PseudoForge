/* ---------------------------------------------------------------------------
 * main.js -- the front page.
 *
 * Three jobs: draw the periodic table, fill the selectors from the API, and
 * wire the four buttons. Every list it shows is fetched; none is hard-coded,
 * because a hard-coded list of engines or functionals is a list that goes
 * stale the day one is added.
 * ------------------------------------------------------------------------- */
'use strict';

const state = { element: null, native: [], xcLabel: new Map(), fmtLabel: new Map(), filter: { cov: null, q: '' }, pickedProfile: null };

/* -- colour theme --------------------------------------------------------- */

/* The theme is stored under one key and applied in three places:
 *
 *   1. before first paint, by a small inline snippet in index.html, so a
 *      reader who chose light does not see a dark flash before this file
 *      loads.  That snippet and this function must agree on the key name
 *      and the two values.
 *   2. on load, from this file, in case the inline snippet ran before
 *      prefers-color-scheme settled -- which it does on some browsers.
 *   3. on every click, saving the choice and toggling the animation class
 *      so the transition plays exactly once.
 *
 * Without the inline snippet the site would still work; it would just blink
 * on every page load for readers who did not pick the default.
 */
function currentTheme() {
  return document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
}

function applyTheme(theme, animate) {
  document.documentElement.dataset.theme = theme;
  if (animate) {
    document.documentElement.classList.add('theme-anim');
    // The transition is one-shot: once it has played, remove the class so
    // a later theme switch is instant if the reader wants it to be.
    setTimeout(() => document.documentElement.classList.remove('theme-anim'), 250);
  }
  const btn = document.getElementById('theme-toggle');
  if (btn) {
    btn.setAttribute('aria-label',
      theme === 'light' ? 'Switch to dark theme' : 'Switch to light theme');
    btn.title = theme === 'light' ? 'Dark' : 'Light';
  }
}

function initTheme() {
  const saved = localStorage.getItem('pf-theme');
  if (saved === 'light' || saved === 'dark') {
    applyTheme(saved, false);
  } else {
    const prefersLight = matchMedia('(prefers-color-scheme: light)').matches;
    applyTheme(prefersLight ? 'light' : 'dark', false);
  }
  const btn = document.getElementById('theme-toggle');
  if (btn && !btn.dataset.wired) {
    btn.dataset.wired = '1';
    btn.addEventListener('click', () => {
      const next = currentTheme() === 'light' ? 'dark' : 'light';
      applyTheme(next, true);
      localStorage.setItem('pf-theme', next);
    });
  }
}

/* -- the periodic table ---------------------------------------------------- */
/* -- table decoration ------------------------------------------------------ */

/* The coverage dots need a legend: three shades and a grey are not
 * self-explanatory, and a reader should not have to click a cell to learn
 * what green means.  Built once, in JS, so the thresholds live next to the
 * code that uses them rather than in a second place that can drift. */
function ensureLegend() {
  const host = document.getElementById('ptable');
  if (!host || document.getElementById('ptable-legend')) return;

  const legend = document.createElement('div');
  legend.id = 'ptable-legend';
  legend.className = 'ptable-legend';
  legend.innerHTML =
    '<button type="button" class="lg-item" data-cov="rich"><span class="dot dot-rich"></span> 50+ files</button>' +
    '<button type="button" class="lg-item" data-cov="some"><span class="dot dot-some"></span> 5\u201349 files</button>' +
    '<button type="button" class="lg-item" data-cov="thin"><span class="dot dot-thin"></span> 1\u20134 files</button>' +
    '<button type="button" class="lg-item" data-cov="none"><span class="dot dot-none"></span> not in store</button>' +
    '<button type="button" class="lg-clear">Clear filter</button>';
  host.parentNode.insertBefore(legend, host.nextSibling);

  /* Wire the buttons here, not in wireTableTools.  A legend that appears
   * but does not respond is worse than no legend, and the failure mode
   * (silent no-op on click) is exactly what happened when the wiring was
   * in a different function that stopped being called. */
  legend.querySelectorAll('.lg-item').forEach((btn) => {
    btn.addEventListener('click', () => {
      const cov = btn.dataset.cov;
      const isOn = btn.classList.contains('on');
      legend.querySelectorAll('.lg-item').forEach((x) => x.classList.remove('on'));
      state.filter.cov = isOn ? null : cov;
      if (!isOn) btn.classList.add('on');
      applyFilters();
    });
  });
  const clearBtn = legend.querySelector('.lg-clear');
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      state.filter.cov = null;
      state.filter.q = '';
      const inp = document.getElementById('ptable-q');
      if (inp) {
        inp.value = '';
        const wrap = inp.closest('.ptable-search');
        if (wrap) wrap.classList.remove('has-value');
        const clr = wrap && wrap.querySelector('.clear');
        if (clr) clr.hidden = true;
      }
      legend.querySelectorAll('.lg-item').forEach((x) => x.classList.remove('on'));
      applyFilters();
    });
  }

  if (!document.getElementById('ptable-key')) {
    const key = document.createElement('div');
    key.id = 'ptable-key';
    key.className = 'ptable-key';
    key.innerHTML =
      '<span class="key-item"><span class="key-swatch key-s"></span> s-block</span>' +
      '<span class="key-item"><span class="key-swatch key-p"></span> p-block</span>' +
      '<span class="key-item"><span class="key-swatch key-d"></span> d-block</span>' +
      '<span class="key-item"><span class="key-swatch key-f"></span> f-block</span>';
    legend.parentNode.insertBefore(key, legend.nextSibling);
  }
}

/* Colour each cell by how many files the store holds for that element.
 * Three buckets, not a continuum: the useful distinction is "plenty",
 * "some" and "a few", and a gradient implies an order that does not exist. */
function paintCoverage() {
  const counts = new Map();
  for (const n of state.native) {
    counts.set(n.element, (counts.get(n.element) || 0) + 1);
  }
  document.querySelectorAll('.el').forEach((cell) => {
    const sym = cell.dataset.symbol;
    const n = counts.get(sym) || 0;
    cell.classList.remove('cov-rich', 'cov-some', 'cov-thin', 'cov-none');
    if (n === 0)      cell.classList.add('cov-none');
    else if (n >= 50) cell.classList.add('cov-rich');
    else if (n >= 5)  cell.classList.add('cov-some');
    else              cell.classList.add('cov-thin');
    if (n > 0) {
      const base = (cell.title || '').split(' — ')[0];
      cell.title = base + ' — ' + n + ' file' + (n === 1 ? '' : 's') + ' in the store';
    }
  });
}

/* Wiring for the search box, the legend buttons, and the double-click on
 * a cell.  Delegated on the table so it survives a redraw. */
function wireTableTools() {
  const host = document.getElementById('ptable');
  if (!host || host.dataset.wired === '1') return;

  if (!document.getElementById('ptable-search')) {
    const head = document.querySelector('.element-head');
    if (head) {
      const tools = document.createElement('div');
      tools.className = 'ptable-tools';
      tools.innerHTML =
        '<div class="ptable-search">' +
          '<input type="search" id="ptable-q" placeholder="Search element — symbol, name, Z" ' +
                 'autocomplete="off" spellcheck="false" aria-label="Search elements">' +
          '<button class="clear" type="button" aria-label="Clear search" hidden>×</button>' +
        '</div>';
      head.appendChild(tools);
    }
  }

  const input = document.getElementById('ptable-q');
  if (input) {
    input.addEventListener('input', () => {
      state.filter.q = input.value;
      const wrap = input.closest('.ptable-search');
      if (wrap) wrap.classList.toggle('has-value', !!input.value);
      const clear = input.parentElement.querySelector('.clear');
      if (clear) clear.hidden = !input.value;
      applyFilters();
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        input.value = ''; state.filter.q = ''; applyFilters(); input.blur();
      }
    });
    const clear = input.parentElement.querySelector('.clear');
    if (clear) clear.addEventListener('click', () => {
      input.value = ''; state.filter.q = ''; applyFilters(); input.focus();
    });
  }

  host.addEventListener('dblclick', (e) => {
    const cell = e.target.closest('.el');
    if (!cell || cell.classList.contains('filtered-out')) return;
    const btn = document.getElementById('btn-here');
    if (btn && !btn.disabled) btn.click();
  });

  host.dataset.wired = '1';
}

/* The filter itself.  Coverage and text are independent -- "show only what
 * is downloadable" and "jump to silicon" are different questions, and a
 * reader may want both at once. */
function applyFilters() {
  const q = (state.filter.q || '').trim().toLowerCase();
  const cov = state.filter.cov;
  let shown = 0;
  document.querySelectorAll('.el').forEach((cell) => {
    const sym = (cell.dataset.symbol || '').toLowerCase();
    const title = (cell.title || '').toLowerCase();
    const inCov =
      (cell.classList.contains('cov-rich') && cov === 'rich') ||
      (cell.classList.contains('cov-some') && cov === 'some') ||
      (cell.classList.contains('cov-thin') && cov === 'thin') ||
      (cell.classList.contains('cov-none') && cov === 'none');
    const covOk = !cov || inCov;
    const qOk = !q || sym.includes(q) || title.includes(q);
    const show = covOk && qOk;
    cell.classList.toggle('filtered-out', !show);
    if (show) shown++;
  });
  const legend = document.getElementById('ptable-legend');
  if (legend) legend.classList.toggle('has-filter', !!(cov || q));
  return shown;
}


async function drawTable() {
  const host = document.getElementById('ptable');
  const { status, body } = await API.elements();
  if (status !== 200 || !Array.isArray(body)) {
    host.innerHTML = '<p class="error">The element table could not be loaded. ' +
                     'The API may be down — see <a href="/docs/">the docs</a>.</p>';
    return;
  }

  /* The grid reserves one column on the left for period numbers and two
   * rows at the bottom for lanthanides and actinides, with one empty row
   * of separation above them.  Everything else is placed by the data:
   * group number becomes column, period becomes row.  An element with
   * period p and group g therefore lands at grid(row=p+1, col=g+1). */
  const grid = document.createElement('div');
  grid.className = 'ptable-grid';

  // Group numbers 1-18 above the main block.
  for (let g = 1; g <= 18; g++) {
    const h = document.createElement('span');
    h.className = 'ptable-group-label';
    h.textContent = g;
    h.style.gridRow = 1;
    h.style.gridColumn = g + 1;
    grid.appendChild(h);
  }

  // Period numbers 1-7 down the left, aligned with their rows.
  for (let p = 1; p <= 7; p++) {
    const h = document.createElement('span');
    h.className = 'ptable-period-label';
    h.textContent = p;
    h.style.gridRow = p + 1;
    h.style.gridColumn = 1;
    grid.appendChild(h);
  }

  /* The convention for the f-block: the label in the left column reads
   * "57–71" and "89–103", pointing at the two detached rows below the
   * main block.  The rows themselves are placed at grid rows 10 and 11
   * (1 for the group-number band, 7 for the main periods, 1 spacer, then
   * the two f-block rows). */
  const lan = document.createElement('span');
  lan.className = 'ptable-series-label';
  lan.textContent = '57–71';
  lan.style.gridRow = 10;
  lan.style.gridColumn = 1;
  grid.appendChild(lan);

  const act = document.createElement('span');
  act.className = 'ptable-series-label';
  act.textContent = '89–103';
  act.style.gridRow = 11;
  act.style.gridColumn = 1;
  grid.appendChild(act);

  body.forEach((el) => {
    const cell = document.createElement('button');
    cell.className = 'el el-' + (el.block || 'x');
    cell.type = 'button';
    cell.dataset.symbol = el.symbol;
    cell.title = `${el.name} (Z = ${el.z})`;
    cell.innerHTML =
      `<span class="z">${el.z}</span>` +
      `<span class="sym">${el.symbol}</span>`;

    let row, col;
    if (el.series === 'lanthanide') {
      row = 10; col = el.z - 54;      /* La = Z 57 -> col 3 */
    } else if (el.series === 'actinide') {
      row = 11; col = el.z - 86;      /* Ac = Z 89 -> col 3 */
    } else {
      row = el.period + 1;            /* +1 for the group-number band */
      col = el.group + 1;             /* +1 for the period-number column */
    }
    cell.style.gridRow = row;
    cell.style.gridColumn = col;

    cell.addEventListener('click', () => choose(el));
    grid.appendChild(cell);
  });

  host.innerHTML = '';
  host.appendChild(grid);

  /* Colour the cells now, in the same tick they were created.  Waiting for
   * loadSelectors to call paintCoverage meant the two raced: whichever
   * finished last won, and if drawTable ran after, the classes were never
   * applied and the legend filter could not find any cell to keep. */
  if (state.native.length) paintCoverage();

  /* Double-click on a cell does what the Download button does, using
   * whatever physics is currently selected.  Attached on the grid rather
   * than on the table so a rebuild replaces it along with the cells. */
  grid.addEventListener('dblclick', (e) => {
    const cell = e.target.closest('.el');
    if (!cell || cell.classList.contains('filtered-out')) return;
    const btn = document.getElementById('btn-here');
    if (btn && !btn.disabled) btn.click();
  });
}

function choose(el) {
  state.element = el;
  document.getElementById('chosen').textContent = `${el.symbol} — ${el.name} (Z = ${el.z})`;

  /* Move the "on" class from wherever it was to where it belongs.  No
   * animation, no scale: the outline does the work.  This is the same
   * approach a print table takes when a reader points at a cell. */
  document.querySelectorAll('.el.on').forEach((n) => n.classList.remove('on'));
  const cell = document.querySelector(`.el[data-symbol="${el.symbol}"]`);
  if (cell) cell.classList.add('on');

  state.pickedProfile = null;
  refillForElement(el, true);
  refresh();
}

/* -- display helpers ------------------------------------------------------ */

/* Bytes as a person reads them.  573 KB, not 586752.  The store keeps files
 * gzipped and reports the compressed size in the index; the download is the
 * decompressed file, so the preview says "≈" to make clear it is the stored
 * size, not a promise about what lands on disk.  The difference matters
 * enough that a wrong exact number would be worse than an honest approximate. */
function fmtSize(n) {
  if (!n && n !== 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0, v = n;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + ' ' + units[i];
}

/* "psl-high · ld1 · norm-conserving" -- the answer to "which file is this?".
 * The id already carries the file name; the profile and engine are what
 * make two files with the same element/xc/family distinguishable. */
function describeFile(m) {
  if (!m) return '';
  const bits = [];
  if (m.profile && m.profile !== 'unknown') bits.push(m.profile);
  if (m.engine && m.engine !== 'unknown') bits.push(m.engine);
  if (m.format) bits.push(m.format.toUpperCase());
  return bits.join(' · ');
}

/* -- the selectors --------------------------------------------------------- */
function fill(id, items, value, label, keep) {
  const sel = document.getElementById(id);
  const current = sel.value;
  sel.innerHTML = '';
  if (keep) sel.appendChild(new Option(keep, ''));
  items.forEach((it) => sel.appendChild(new Option(label(it), value(it))));
  if (current) sel.value = current;
}

/* The form offers what exists, not what the registry can name.
 *
 * It used to be filled from /api/xc, which is the full exchange-correlation
 * registry: 33 functionals, of which about twenty are proxies -- pick SCAN
 * and ld1.x has no meta-GGA solver, so you get a PBE pseudopotential with a
 * SCAN label on it. The command line prints "generated with PBE" next to
 * that choice and a person reading a terminal sees it. A dropdown on a web
 * page does not carry that warning anywhere the eye lands, and no published
 * library ships a meta-GGA, hybrid or vdW pseudopotential anyway, so none of
 * them will ever be in the store.
 *
 * So the lists come from the store. Every option you can pick is an option
 * that resolves to a real file, and the list grows by itself as the store
 * does. When the store is empty the page says so rather than presenting a
 * menu that cannot be satisfied. */
function uniq(rows, key) {
  return [...new Set(rows.map((r) => r[key]).filter((v) => v && v !== 'unknown'))].sort();
}

const FAMILY = { nc: 'Norm-conserving', us: 'Ultrasoft', paw: 'PAW' };
const REL = { scalar: 'Scalar', full: 'Full (spin–orbit)', nonrel: 'Non-relativistic' };

/* Refill the three physics dropdowns from only the rows that match the chosen
 * element.  Without this every element showed every functional in the store:
 * pick silicon and you could select "vwn" though no VWN silicon file exists,
 * and the page would then say "not available here".  It was correct -- it just
 * made the user discover the store's contents by trial and error.
 *
 * The current selection is kept when it survives the filter (fill() restores
 * it by value), so switching from one element to another does not silently
 * reset a functional you already picked if both elements have it.  When it
 * does not survive, the first available option takes over; refresh() then
 * reports what that choice resolves to. */
function refillForElement(el, keep) {
  const base = el ? state.native.filter((n) => n.element === el.symbol) : state.native;

  /* Cascade: each dropdown offers only the choices that are reachable given
   * the ones above it.  Without this, picking Al and PAW still showed WC in
   * the functional list -- there is no PAW/WC aluminium file, and the page
   * only said so after the choice was made.  The order is functional ->
   * family -> relativity -> format, because that is the order a person
   * decides them in: the physics first, the container last.
   *
   * `keep` says whether to preserve the current dropdown value if it still
   * exists.  It is true when the user is only changing the element, false
   * when they changed a physics choice themselves -- in that case the
   * value they just set is the one to keep, and the ones below it follow.
   */
  const curXc  = keep ? document.getElementById('xc').value     : null;
  const curFam = keep ? document.getElementById('family').value : null;
  const curRel = keep ? document.getElementById('rel').value    : null;

  fill('xc', uniq(base, 'xc'), (v) => v, (v) => state.xcLabel.get(v) || v.toUpperCase());
  if (curXc && base.some((n) => n.xc === curXc)) {
    document.getElementById('xc').value = curXc;
  }
  const xc = document.getElementById('xc').value;

  const forXc = base.filter((n) => n.xc === xc);
  fill('family', uniq(forXc, 'family'), (v) => v, (v) => FAMILY[v] || v.toUpperCase());
  if (curFam && forXc.some((n) => n.family === curFam)) {
    document.getElementById('family').value = curFam;
  }
  const family = document.getElementById('family').value;

  const forFam = forXc.filter((n) => n.family === family);
  fill('rel', uniq(forFam, 'relativity'), (v) => v, (v) => REL[v] || v);
  if (curRel && forFam.some((n) => n.relativity === curRel)) {
    document.getElementById('rel').value = curRel;
  }
  const rel = document.getElementById('rel').value;

  /* Format is last because it is the only choice the server can change for
   * you.  Offer (a) the formats actually held for this exact physics, plus
   * (b) whatever a non-refused conversion reaches from them.  A format that
   * exists elsewhere in the store but not here is not offered, because
   * picking it would end in no_such_path after the click rather than before
   * it.  The current pick is preserved if it survives the filter. */
  const candidates = forFam.filter((n) => n.relativity === rel);
  const heldFmt = new Set(candidates.map((n) => n.format));
  const reachable = new Set(heldFmt);
  for (const cv of state.conversions) {
    if (heldFmt.has(cv.from)) reachable.add(cv.to);
  }
  const curFmt = document.getElementById('format').value;
  fill('format', [...reachable].sort(), (v) => v, (v) => state.fmtLabel.get(v) || v.toUpperCase());
  if (curFmt && reachable.has(curFmt)) {
    document.getElementById('format').value = curFmt;
  }
}

/* -- coverage colouring --------------------------------------------------- */

/* Three buckets, not a continuous scale: the useful distinction is "many",
 * "some" and "a few", and a gradient would imply an order that does not
 * exist.  The classes are additive on top of .el so the block colour still
 * shows through; the CSS decides how strong the tint is. */
function paintCoverage() {
  const counts = new Map();
  for (const n of state.native) {
    counts.set(n.element, (counts.get(n.element) || 0) + 1);
  }
  document.querySelectorAll('.el').forEach((cell) => {
    const sym = cell.dataset.symbol;
    const n = counts.get(sym) || 0;
    cell.classList.remove('cov-rich', 'cov-some', 'cov-thin', 'cov-none');
    if (n === 0)      cell.classList.add('cov-none');
    else if (n >= 50) cell.classList.add('cov-rich');
    else if (n >= 5)  cell.classList.add('cov-some');
    else              cell.classList.add('cov-thin');
    if (n > 0) {
      const base = (cell.title || '').split(' — ')[0];
      cell.title = `${base} — ${n} file${n === 1 ? '' : 's'} in the store`;
    }
  });
  /* If a filter is active when the table is re-coloured (after the store
   * loads, say), it has to be reapplied -- the classes that carry the
   * coverage just changed. */
  if (state.filter && (state.filter.cov || state.filter.q)) applyFilters();
}

/* -- table tools: search, filter, double-click ------------------------------ */

/* Which coverage bucket a cell belongs to, as a string.  Reads the class
 * rather than recomputing the count, so paintCoverage stays the one place
 * that decides what "rich" and "thin" mean. */
function covOf(cell) {
  if (cell.classList.contains('cov-rich')) return 'rich';
  if (cell.classList.contains('cov-some')) return 'some';
  if (cell.classList.contains('cov-thin')) return 'thin';
  if (cell.classList.contains('cov-none')) return 'none';
  return 'unknown';
}

/* Apply the current filter to every cell.  A cell is visible if it matches
 * both the coverage filter (if any) and the search query (if any).  The two
 * are independent: "show only what I can download" and "jump to silicon"
 * are different questions and should compose. */
function applyFilters() {
  const q = state.filter.q.trim().toLowerCase();
  const cov = state.filter.cov;
  let shown = 0;
  document.querySelectorAll('.el').forEach((cell) => {
    const sym = (cell.dataset.symbol || '').toLowerCase();
    const title = (cell.title || '').toLowerCase();
    const covHere = covOf(cell);
    const covOk = !cov || cov === covHere;
    const qOk = !q || sym.includes(q) || title.includes(q);
    const show = covOk && qOk;
    cell.classList.toggle('filtered-out', !show);
    if (show) shown++;
  });
  document.getElementById('ptable-legend')
    ?.classList.toggle('has-filter', !!(cov || q));
  return shown;
}

/* Build the search box, wire the legend, and set up one delegated handler
 * for the whole table.  Everything goes through delegation because the
 * table is rebuilt by drawTable when the page is reloaded by instant
 * navigation, and per-cell listeners would be lost.  One listener on a
 * stable ancestor survives that. */
function wireTableTools() {
  const host = document.getElementById('ptable');
  if (!host || host.dataset.wired === '1') return;

  // 1. search box, inserted into the element-head panel -- beside the intro
  // text, not above the table.  The table is the thing being searched; the
  // search box belongs next to the label that says what it searches.
  if (!document.getElementById('ptable-search')) {
    const head = document.querySelector('.element-head');
    if (!head) { console.warn('element-head not found, search box skipped'); return; }
    const tools = document.createElement('div');
    tools.className = 'ptable-tools';
    tools.innerHTML = `
      <div class="ptable-search">
        <input type="search" id="ptable-q"
               placeholder="Search element — symbol, name, Z"
               autocomplete="off" spellcheck="false"
               aria-label="Search elements">
        <button class="clear" type="button" aria-label="Clear search">×</button>
      </div>
    `;
    head.appendChild(tools);
  }

  const input = document.getElementById('ptable-q');
  const wrap = input.closest('.ptable-search');
  const clear = wrap.querySelector('.clear');

  input.addEventListener('input', () => {
    state.filter.q = input.value;
    wrap.classList.toggle('has-value', !!input.value);
    applyFilters();
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      input.value = '';
      state.filter.q = '';
      wrap.classList.remove('has-value');
      applyFilters();
      input.blur();
    }
    if (e.key === 'Enter') {
      const first = document.querySelector('.el:not(.filtered-out)');
      if (first) {
        first.click();
        first.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
    }
  });
  clear.addEventListener('click', () => {
    input.value = '';
    state.filter.q = '';
    wrap.classList.remove('has-value');
    applyFilters();
    input.focus();
  });

  // 2. legend as filter toggles (rebuilt on each ensureLegend call)
  const legend = document.getElementById('ptable-legend');
  if (legend && !legend.dataset.lgWired) {
    legend.dataset.lgWired = '1';
    legend.querySelectorAll('.lg-item').forEach((item) => {
      item.addEventListener('click', () => {
        const cov = item.dataset.cov;
        const wasOn = item.classList.contains('on');
        legend.querySelectorAll('.lg-item').forEach((x) => x.classList.remove('on'));
        if (wasOn) {
          state.filter.cov = null;
        } else {
          state.filter.cov = cov;
          item.classList.add('on');
        }
        applyFilters();
      });
    });
    const clearBtn = legend.querySelector('.lg-clear');
    clearBtn?.addEventListener('click', () => {
      state.filter.cov = null;
      state.filter.q = '';
      const inp = document.getElementById('ptable-q');
      if (inp) { inp.value = ''; inp.closest('.ptable-search')?.classList.remove('has-value'); }
      legend.querySelectorAll('.lg-item').forEach((x) => x.classList.remove('on'));
      applyFilters();
    });
  }

  // 3. delegated handlers on the table itself
  host.addEventListener('dblclick', (e) => {
    const cell = e.target.closest('.el');
    if (!cell || cell.classList.contains('filtered-out')) return;
    // choose() already fired from the two clicks that preceded this event,
    // so state.match is up to date.  Only the button's own disabled flag
    // gates the download.
    const btn = document.getElementById('btn-here');
    if (btn && !btn.disabled) btn.click();
  });

  host.dataset.wired = '1';


  // 4. "Also" buttons in the preview card are delegated on the card itself,
  // which is rebuilt on every refresh and cannot hold its own listeners.
  const preview = document.getElementById('file-preview');
  if (preview && !preview.dataset.wired) {
    preview.dataset.wired = '1';
    preview.addEventListener('click', (e) => {
      const btn = e.target.closest('.pv-alt');
      if (!btn) return;
      e.preventDefault();
      const p = btn.dataset.profile;
      state.pickedProfile = p || null;
      refresh();
    });
  }
}

async function loadSelectors() {
  const [native, xc, formats] = await Promise.all([
    API.native(), API.xc(), API.formats(),
  ]);

  state.native = (native.status === 200 && Array.isArray(native.body)) ? native.body : [];

  /* Labels still come from the registries -- "Perdew-Burke-Ernzerhof" is
   * better than "pbe" -- but the *set* comes from the store. */
  state.xcLabel = new Map(
    (xc.status === 200 ? xc.body : []).map((x) => [x.id, x.label]));
  state.fmtLabel = new Map(
    (formats.status === 200 && formats.body.formats ? formats.body.formats : [])
      .map((f) => [f.id, f.label]));
  const xcLabel = state.xcLabel;
  const fmtLabel = state.fmtLabel;

  if (!state.native.length) {
    document.getElementById('summary').textContent =
      'Nothing is built on this server yet.';
    show(
      `<h3>The store is empty</h3>
       <p>This server holds pre-built files and converts between formats. It
          does not run the engines, so it cannot make one on demand
          — <a href="/docs/architecture/http/">why</a>. Until the store is
          populated, every answer here is the build-locally command.</p>`,
      'refused');
    return;
  }

  /* Before an element is chosen, no physics choice is meaningful yet --
   * every option here was reachable only from a specific element.  Leave
   * the lists empty and put a marker in the first slot so the page does
   * not present a menu that is not yet a menu. */
  fill('xc',     [], (v) => v, (v) => v);
  fill('family', [], (v) => v, (v) => v);
  fill('rel',    [], (v) => v, (v) => v);
  document.getElementById('xc').appendChild(new Option('Select an element first', ''));
  document.getElementById('family').appendChild(new Option('Select an element first', ''));
  document.getElementById('rel').appendChild(new Option('Select an element first', ''));

  /* Formats: the ones held, plus the ones a registered conversion can reach
   * from them. A format nothing can produce is not offered. */
  /* Keep the conversion table for per-selection filtering below.  Building
   * the format list once from the whole store is what offered "GTH" for a
   * silicon selection that only had UPF, and then failed at click time with
   * no_such_path: the format was globally held, not held *for this element*.
   * The format choice is made last and depends on the three physics choices
   * above it, so it is filled from refillForElement, not here. */
  state.conversions = (formats.status === 200 && Array.isArray(formats.body.conversions))
    ? formats.body.conversions.filter((c) => c.kind !== 'refused')
    : [];
  fill('format', [], (v) => v, (v) => v);
  document.getElementById('format').appendChild(new Option('Select an element first', ''));

  /* Now that the store is loaded, colour the table by coverage and add the
   * legend that explains the colours.  The count per element comes straight
   * from the fetched index, not a second request.  ensureLegend() is
   * idempotent, so calling it here and in drawTable is safe. */
  paintCoverage();
  ensureLegend();
}

/* -- what is available for the current choice ------------------------------ */
/* The store is fetched once and filtered here. It used to be matched on the
 * element alone -- `find((n) => n.element === el.symbol)` -- so asking for
 * ultrasoft LDA and being handed a PAW PBE file was not a bug you could see.
 * The physics in the form is the physics that has to match. */
function want() {
  return {
    xc:     document.getElementById('xc').value,
    family: document.getElementById('family').value,
    rel:    document.getElementById('rel').value,
    format: document.getElementById('format').value,
  };
}

/* -- the preview card ----------------------------------------------------- */

/* Renders the file the Download button will serve, or clears the card.
 * The point is that nothing here is a surprise after the click: the name,
 * the size, which library and which engine produced it, and whether the
 * server is going to convert on the way out (in which case the served name
 * may differ from the stored one).  When several files match the physics,
 * the alternatives are listed too -- the user asked for a physics, not a
 * library, and the library is a valid second choice to offer. */

/* ---------------------------------------------------------------------------
 * Profile preference.
 *
 * When a reader has not chosen a library explicitly, the first candidate
 * for the current physics is whatever order the index happens to be in.
 * That produced unpredictable defaults -- sometimes psl-low, sometimes
 * psl-tot.  The list below says which profiles are considered better, and
 * the sort puts the best available one first.  Anything not in the list
 * keeps its index order at the end.
 *
 * "Best" here means: higher cutoff precision first, more functions per
 * element second.  psl-high is above psl-low is above psl-tot; sg15 is
 * preferred over gbrv for the same reason; adpack is last because its
 * files are in a format QE cannot read directly.
 * ------------------------------------------------------------------------- */
const PROFILE_ORDER = [
  'psl-high', 'psl-low', 'psl-031', 'psl-alt', 'psl-tot',
  'sg15', 'gbrv', 'vanderbilt', 'fhi', 'hgh', 'cp2k-gth',
  'marburg', 'gipaw', 'pseudodojo', 'adpack',
];
function profileRank(p) {
  const i = PROFILE_ORDER.indexOf(p);
  return i < 0 ? PROFILE_ORDER.length : i;
}

function setPreview(match, all, w) {
  const box = document.getElementById('file-preview');
  if (!box) return;
  if (!match) { box.hidden = true; box.innerHTML = ''; return; }

  const name = match.id.split('_').pop() || match.id;
  const size = fmtSize(match.size);
  const desc = describeFile(match);
  const willConvert = match.format !== w.format;

  let html = '<div class="pv-row">' +
    '<span class="pv-label">File</span>' +
    `<span class="pv-value"><code>${name}</code></span>` +
  '</div>';

  if (desc) {
    html += '<div class="pv-row">' +
      '<span class="pv-label">Source</span>' +
      `<span class="pv-value">${desc}</span>` +
    '</div>';
  }

  if (size) {
    html += '<div class="pv-row">' +
      '<span class="pv-label">Size</span>' +
      `<span class="pv-value">≈ ${size} stored</span>` +
    '</div>';
  }

  if (willConvert) {
    html += '<div class="pv-row">' +
      '<span class="pv-label">Convert</span>' +
      `<span class="pv-value">${match.format} → ${w.format} on the server</span>` +
    '</div>';
  }

  /* The other profiles that hold this element in this physics.  They are
   * buttons, not text: if a reader can see that another library has the
   * same file, they should be able to ask for it without re-deriving the
   * choice from the dropdowns.  The current profile is shown as a label
   * because it is already the answer. */
  /* The other profiles that hold this element in this physics.  Sorted by
   * preference, best first, so a reader who wants a different library sees
   * the alternatives in the order they would look for them.  The currently
   * shown profile is not in this list -- it is already the answer. */
  const alts = [...new Set(all.map((n) => n.profile).filter((p) => p && p !== 'unknown'))]
    .sort((a, b) => profileRank(a) - profileRank(b));
  if (alts.length > 1) {
    const others = alts.filter((p) => p !== match.profile);
    const buttons = others.map((p) =>
      `<button type="button" class="pv-alt" data-profile="${p}" ` +
      `title="Use the ${p} file instead">${p}</button>`
    ).join('');
    html += '<div class="pv-row pv-alt-row">' +
      '<span class="pv-label">Also</span>' +
      `<span class="pv-value">${buttons}</span>` +
    '</div>';
  }
  /* When the reader has pinned a profile, show it as pinned and offer to
   * release the pin.  This is the only way back to the default once a pin
   * has been set, so it has to be visible. */
  if (state.pickedProfile) {
    html += '<div class="pv-row">' +
      '<span class="pv-label">Pinned</span>' +
      `<span class="pv-value">${state.pickedProfile} ` +
      `<button type="button" class="pv-alt pv-alt-clear" data-profile="">release</button></span>` +
    '</div>';
  }

  box.innerHTML = html;
  box.hidden = false;
}

async function refresh() {
  const el = state.element;
  const btnHere = document.getElementById('btn-here');
  const btnCompare = document.getElementById('btn-compare');
  const summary = document.getElementById('summary');

  if (!el) return;
  const w = want();
  summary.textContent =
    `${el.symbol} · ${w.xc.toUpperCase()} · ${w.family.toUpperCase()} · ${w.rel}`;

  /* Everything the store holds for this element and this physics. Format is
   * not part of the match: a different format is a conversion, which the
   * server can do. A different family or functional is a different physical
   * object, which it cannot. */
  const base = state.native.filter((n) =>
    n.element === el.symbol &&
    n.xc === w.xc &&
    n.family === w.family &&
    n.relativity === w.rel);

  /* Sort by profile preference so the default (no pickedProfile) lands on
   * the best library rather than whichever one happened to be indexed
   * first.  Sorting is stable in modern JS, so equal-rank entries keep
   * their index order. */
  base.sort((a, b) => profileRank(a.profile) - profileRank(b.profile));
  /* If the reader has picked a specific profile from the "Also" list, that
   * profile wins.  Otherwise the first candidate for the requested format
   * is used.  Reset pickedProfile when the element or physics changes --
   * a profile that was valid for one element is usually not valid for the
   * next, and silently keeping it would make the picker feel stuck. */
  const candidates = state.pickedProfile
    ? [...base].sort((a, b) =>
        (a.profile === state.pickedProfile ? -1 : 0) -
        (b.profile === state.pickedProfile ? -1 : 0))
    : base;

  /* Prefer one already in the format asked for, so the common case needs no
   * conversion at all. */
  state.match = candidates.find((n) => n.format === w.format) || candidates[0];

  btnHere.disabled = !state.match;
  btnCompare.disabled = !state.match;

  if (!state.match) {
    btnHere.textContent = 'Not available here';
    setPreview(null);
    showMiss(el, w);
    return;
  }

  /* Show what the button will hand over before it is pressed.  The match is
   * resolved by the time we get here; this is where its filename, size and
   * origin become visible, instead of appearing only in the browser's
   * download shelf after the click. */
  setPreview(state.match, candidates, w);
  btnHere.textContent = state.match.format === w.format
    ? `Download ${w.format.toUpperCase()}`
    : `Convert to ${w.format.toUpperCase()} and download`;
  showHave(state.match, w);
}

/* What we hold, and who published it. This is where the library and the
 * engine belong: as provenance on an answer, not as a question asked before
 * the user knows what they are choosing between. */
function showHave(m, w) {
  const official = OFFICIAL[m.profile];
  const same = m.format === w.format;
  const conv = same ? '' : ' -- will be converted to ' + w.format.toUpperCase();
  show(
    `<h3>Available here</h3>
     <dl class="prov">
       <dt>Library</dt><dd>${esc(m.profile)}</dd>
       <dt>Engine</dt><dd>${esc(m.engine)}</dd>
       <dt>Stored as</dt><dd>${esc(m.format.toUpperCase())}${esc(conv)}</dd>
     </dl>
     ${official ? `<p>This is what <strong>${esc(m.profile)}</strong> publishes.
        You can take the authors&rsquo; own copy instead:
        <a href="${esc(official)}" target="_blank" rel="noopener">${esc(official)}</a></p>` : ''}`,
    'ok');
}

/* A miss is an answer too, and the server cannot fill it: it does not run
 * engines. Say what to do instead rather than leaving a disabled button and
 * no explanation. */
function showMiss(el, w) {
  const cmd = buildCmd(el.symbol, w, null);
  show(
    `<h3 data-status="miss">Not pre-built here</h3>
     <p>Nothing in the store matches
        <strong>${esc(el.symbol)} · ${esc(w.xc.toUpperCase())} ·
        ${esc(w.family.toUpperCase())} · ${esc(w.rel)}</strong>.
        This server converts formats; it does not run engines, so it cannot
        make one. <a href="/docs/architecture/http/">Why</a>.</p>
     <pre>${esc(cmd)}</pre>
     <p><a class="btn" href="/docs/getting-started/installation/">Install PseudoForge</a></p>`,
    'refused');
}

/* -- the four buttons ------------------------------------------------------ */
function show(html, kind) {
  const out = document.getElementById('output');
  out.hidden = false;
  out.className = 'output ' + (kind || '');
  out.innerHTML = html;
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

async function onHere() {
  const m = state.match;
  if (!m) return;
  const wanted = want().format;

  if (m.format === wanted) {
    window.location = API.downloadUrl(m.id);
    return;
  }

  show('<p>Converting…</p>');
  const { status, body } = await API.convert(m.id, wanted);

  if (status === 409) {
    /* A refusal is an answer, and there are two different answers. Saying
       "not a missing feature" about both was wrong once the psp8 paths became
       no-tool refusals: for those something IS missing, it is just not
       something you can install. The core sends which kind; the page repeats
       it rather than deciding for itself. */
    const noTool = body.refusal === 'no-tool';
    const tail = noTool
      ? `<p>The conversion is possible in principle and no program performs it.
            For <code>psp8</code>, generate it instead — ONCVPSP writes it
            natively. See
            <a href="/docs/how-to/convert-formats/">Converting formats</a>.</p>`
      : `<p>This is not a missing feature: the target format needs numbers the
            source does not contain. See
            <a href="/docs/reference/formats/">Formats and conversions</a>.</p>`;
    show(
      `<h3>That conversion is refused</h3>
       <p><code>${esc(body.from)}</code> to <code>${esc(body.to)}</code>
          — <em>${esc(body.refusal || 'physics')}</em></p>
       <blockquote>${esc(body.reason)}</blockquote>
       ${tail}`,
      'refused');
    return;
  }
  if (status !== 200) {
    show(`<h3>${esc(body.error || 'Something went wrong')}</h3>
          <p>${esc(body.message || '')}</p>`, 'error');
    return;
  }

  const warn = body.warnings
    ? `<p class="warn"><strong>Warning:</strong> ${esc(body.warnings)}</p>` : '';
  show(
    `<h3>Ready</h3>
     <p>${esc(body.from)} → ${esc(body.to)}, <strong>${esc(body.kind)}</strong>,
        by ${esc(body.tool)} — ${Number(body.size).toLocaleString()} bytes.</p>
     ${warn}
     <p><a class="btn primary" href="${esc(body.download)}">Download the file</a></p>`,
    'ok');
}


/* The command names a library only when one is actually implied -- by the
 * file we matched. Printing `-p psl-high` because that happened to be first
 * in a dropdown told people to reproduce a library they had not chosen. */
function buildCmd(sym, w, profile) {
  return `pseudoforge generate -e ${sym}` +
    ` -t ${w.family}` +
    (profile ? ` -p ${profile}` : '') +
    ` -x ${w.xc}` +
    ` -r ${w.rel}` +
    (w.format && w.format !== 'upf' ? ` --format ${w.format}` : '') +
    ` -o ./out`;
}

function onBuild() {
  const el = state.element ? state.element.symbol : '<element>';
  const cmd = buildCmd(el, want(), state.match ? state.match.profile : null);

  show(
    `<h3>Build it on your machine</h3>
     <p>Generation does not run on this server — it needs the engines, and
        this is a small VPS that deliberately does not have them.
        <a href="/docs/architecture/http/">Why</a>.</p>
     <pre id="cmd">${esc(cmd)}</pre>
     <p>
       <button class="btn" id="copy">Copy</button>
       <a class="btn" href="/docs/getting-started/installation/">Install PseudoForge</a>
       <a class="btn" href="/docs/tutorials/01-carbon/">Follow a tutorial</a>
     </p>`);

  document.getElementById('copy').addEventListener('click', () => {
    navigator.clipboard.writeText(cmd).then(() => {
      document.getElementById('copy').textContent = 'Copied';
    });
  });
}

function onCompare() {
  show(
    `<h3>Compare two files</h3>
     <p>Download one from here and one from the authors, then diff them
        channel by channel:</p>
     <pre>pseudoforge compare ./from-this-site.UPF ./from-the-authors.UPF</pre>
     <p>It reports valence charge, projectors, grid and suggested cutoffs.
        Add <code>--ecut N</code> to compare at one cutoff.</p>
     <p>Or upload one to <a href="/validate/">the validator</a> to see its
        structural report.</p>`);
}

/* -- go -------------------------------------------------------------------- */
document.addEventListener('DOMContentLoaded', async () => {
  /* Selectors first: refresh() filters the store, and drawTable's click
   * handler calls refresh(). Drawing the table before the store is loaded
   * meant the first element clicked was matched against an empty list. */
  await loadSelectors();
  drawTable();
  ['xc', 'family', 'rel', 'format'].forEach((id) =>
    document.getElementById(id).addEventListener('change', refresh));
  /* When the user changes functional or family, cascade the choices below
   * it without losing their own pick.  `keep=false` means "this change is
   * the new truth; rebuild the lists from it".  Element stays the anchor. */
  ['xc', 'family', 'rel'].forEach((id) => {
    document.getElementById(id).addEventListener('change', () => {
      refillForElement(state.element, false);
      refresh();
    });
  });

  document.getElementById('btn-here').addEventListener('click', onHere);
  document.getElementById('btn-build').addEventListener('click', onBuild);
  document.getElementById('btn-compare').addEventListener('click', onCompare);
});


/* ---------------------------------------------------------------------------
 * "Also" chips in the preview card -- PF_ALSO_DELEGATE_V1
 *
 * The chips are the only way to reach a file that exists under a different
 * library's name for the same element and physics.  Two earlier attempts
 * wired them on the container element and broke when the container was
 * re-rendered or when the wiring ran before the container existed.
 *
 * This is delegated on document, which is always present and never
 * re-rendered.  A click anywhere is examined; if it started on a
 * .pv-alt button, the profile is set and refresh() is called.  Nothing
 * else in the page uses that class, so there is no collision.
 * ------------------------------------------------------------------------- */
(function installAlsoDelegate() {
  // Only install once, even if main.js is loaded twice (e.g. by an old
  // service worker plus a fresh page).
  if (window.__pfAlsoDelegateInstalled) return;
  window.__pfAlsoDelegateInstalled = true;

  document.addEventListener('click', function (ev) {
    const btn = ev.target.closest('.pv-alt');
    if (!btn) return;

    ev.preventDefault();
    ev.stopPropagation();

    const picked = btn.dataset.profile || null;

    // state may not exist yet in the very first tick -- but if we got a
    // click, the page has initialised, so this is safe.
    if (typeof state === 'undefined') return;

    state.pickedProfile = picked;

    // Re-run the selection logic so the preview and summary update.  Both
    // are pure functions of state, so calling refresh is enough.
    try {
      if (typeof refresh === 'function') {
        refresh();
      }
    } catch (err) {
      console.error('[pf-also] refresh failed:', err);
    }
  }, true);  // capture: true so nothing else swallows the click first
})();
