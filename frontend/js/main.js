/* ---------------------------------------------------------------------------
 * main.js -- the front page.
 *
 * Three jobs: draw the periodic table, fill the selectors from the API, and
 * wire the four buttons. Every list it shows is fetched; none is hard-coded,
 * because a hard-coded list of engines or functionals is a list that goes
 * stale the day one is added.
 * ------------------------------------------------------------------------- */
'use strict';

const state = { element: null, native: [], xcLabel: new Map(), fmtLabel: new Map(), filter: { cov: null, q: '' }, pickedProfile: null, conversions: [], storeFailed: false, action: 0 };

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

async function drawTable() {
  const host = document.getElementById('ptable');
  host.setAttribute('aria-busy', 'true');
  const { status, body } = await API.elements();
  host.removeAttribute('aria-busy');
  if (status !== 200 || !Array.isArray(body)) {
    host.innerHTML = '<p class="error">The element table could not be loaded. ' +
                     'The API may be down — see <a href="/docs/">the docs</a>.</p>';
    API.notify('The element table could not be loaded.');
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
    cell.setAttribute('aria-label', `${el.symbol} — ${el.name} (Z = ${el.z})`);
    cell.setAttribute('aria-pressed', 'false');
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
  paintCoverage();
  restoreSelection();

  ensureLegend();
  wireTableTools();
}

function restoreSelection() {
  const q = new URLSearchParams(location.search);
  const cell = [...document.querySelectorAll('.el')].find(n => n.dataset.symbol === q.get('e'));
  if (!cell) return;
  cell.click();
  refillForElement(state.element, {
    xc: q.get('xc'), family: q.get('f'), rel: q.get('r'), format: q.get('fmt'),
  });
  state.pickedProfile = q.get('p');
  refresh();
}

function choose(el) {
  state.element = el;
  document.getElementById('chosen').textContent = `${el.symbol} — ${el.name} (Z = ${el.z})`;
  document.querySelectorAll('.el.on').forEach(n => {
    n.classList.remove('on');
    n.setAttribute('aria-pressed', 'false');
  });
  const cell = document.querySelector(`.el[data-symbol="${el.symbol}"]`);
  cell.classList.add('on');
  cell.setAttribute('aria-pressed', 'true');
  state.pickedProfile = null;
  refillForElement(el);
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
function fill(id, items, value, label, preferred) {
  const sel = document.getElementById(id);
  sel.replaceChildren(...items.map(it => new Option(label(it), value(it))));
  sel.disabled = !items.length;
  if (!items.length) sel.appendChild(new Option(state.element ? 'No stored options' : 'Select an element first', ''));
  else if ([...sel.options].some(o => o.value === preferred)) sel.value = preferred;
  return sel.value;
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
function refillForElement(el, preferred = want()) {
  const base = el ? state.native.filter(n => n.element === el.symbol) : [];
  const xc = fill('xc', uniq(base, 'xc'), v => v, v => state.xcLabel.get(v) || v.toUpperCase(), preferred.xc);
  const forXc = base.filter(n => n.xc === xc);
  const family = fill('family', uniq(forXc, 'family'), v => v, v => FAMILY[v] || v.toUpperCase(), preferred.family);
  const forFam = forXc.filter(n => n.family === family);
  const rel = fill('rel', uniq(forFam, 'relativity'), v => v, v => REL[v] || v, preferred.rel);
  const held = new Set(forFam.filter(n => n.relativity === rel).map(n => n.format));
  const reachable = new Set(held);
  for (const cv of state.conversions) {
    if (held.has(cv.from)) reachable.add(cv.to);
  }
  fill('format', [...reachable].sort(), v => v, v => state.fmtLabel.get(v) || v.toUpperCase(), preferred.format);
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
    cell.disabled = !show;
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

  state.storeFailed = native.status !== 200 || !Array.isArray(native.body);
  state.native = state.storeFailed ? [] : native.body;
  state.xcLabel = new Map((xc.status === 200 && Array.isArray(xc.body) ? xc.body : []).map(x => [x.id, x.label]));
  state.fmtLabel = new Map((formats.status === 200 && Array.isArray(formats.body?.formats)
    ? formats.body.formats : []).map(f => [f.id, f.label]));
  state.conversions = formats.status === 200 && Array.isArray(formats.body?.conversions)
    ? formats.body.conversions.filter(c => c.kind !== 'refused') : [];
  if (state.storeFailed) {
    show('<h3>Store unavailable</h3><p>Reload to try again, or <a href="/docs/">open the documentation</a>.</p>', 'error');
  } else if (!state.native.length) {
    show('<h3>The store is empty</h3><p>Choose an element to get a local generation command.</p>', 'refused');
  }
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
    `<span class="pv-value"><code>${esc(name)}</code></span>` +
  '</div>';

  if (desc) {
    html += '<div class="pv-row">' +
      '<span class="pv-label">Source</span>' +
      `<span class="pv-value">${esc(desc)}</span>` +
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
      `<span class="pv-value">${esc(match.format)} → ${esc(w.format)} on the server</span>` +
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
      `<button type="button" class="pv-alt" data-profile="${esc(p)}" ` +
      `title="Use the ${esc(p)} file instead">${esc(p)}</button>`
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
      `<span class="pv-value">${esc(state.pickedProfile)} ` +
      `<button type="button" class="pv-alt pv-alt-clear" data-profile="">release</button></span>` +
    '</div>';
  }

  box.innerHTML = html;
  box.hidden = false;
}

function refresh() {
  const el = state.element;
  const btnHere = document.getElementById('btn-here');
  const btnCompare = document.getElementById('btn-compare');
  const summary = document.getElementById('summary');

  if (!el) return;
  state.action++;
  document.getElementById('btn-build').disabled = false;
  document.getElementById('output').removeAttribute('aria-busy');
  const w = want();
  summary.textContent = [el.symbol, w.xc.toUpperCase(), w.family.toUpperCase(), w.rel].filter(Boolean).join(' · ');

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
  const candidates = base.filter(n => n.format === w.format ||
    state.conversions.some(c => c.from === n.format && c.to === w.format));
  if (!candidates.some(n => n.profile === state.pickedProfile)) state.pickedProfile = null;
  const preferred = state.pickedProfile ? candidates.filter(n => n.profile === state.pickedProfile) : candidates;
  state.match = preferred.find(n => n.format === w.format) || preferred[0];
  const url = new URL(location.href);
  for (const [key, value] of Object.entries({e: el.symbol, xc: w.xc, f: w.family, r: w.rel, fmt: w.format, p: state.pickedProfile})) {
    if (value) url.searchParams.set(key, value);
    else url.searchParams.delete(key);
  }
  history.replaceState(null, '', url);

  btnHere.disabled = !state.match;
  btnCompare.disabled = !state.match;

  if (!state.match) {
    btnHere.textContent = 'Not available here';
    setPreview(null);
    showMiss(el);
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
function showMiss(el) {
  show(`<h3 data-status="miss">${state.storeFailed ? 'Store unavailable' : 'Not pre-built here'}</h3>
    <p>${state.storeFailed ? 'The store could not be checked.' : `No stored file is available for ${esc(el.name)}.`}
    Use <strong>Build locally</strong> for a command checked by PseudoForge.</p>`, 'refused');
}


/* -- the four buttons ------------------------------------------------------ */
function show(html, kind) {
  const out = document.getElementById('output');
  out.hidden = false;
  out.className = 'output ' + (kind || '');
  out.innerHTML = html;
  if (kind === 'error') API.notify(out.querySelector('h3')?.textContent || 'The request failed.');
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

  const action = ++state.action;
  const button = document.getElementById('btn-here');
  button.disabled = true;
  document.getElementById('output').setAttribute('aria-busy', 'true');
  show('<p class="loading" role="status">Converting…</p>');
  const { status, body } = await API.convert(m.id, wanted);
  if (action !== state.action) return;
  button.disabled = false;
  document.getElementById('output').removeAttribute('aria-busy');

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


async function onBuild() {
  if (!state.element) return;
  const w = want();
  const args = { element: state.element.symbol };
  if (w.family) args.family = w.family;
  if (w.xc) args.xc = w.xc;
  if (w.rel) args.relativity = w.rel;
  if (w.format) args.format = w.format;
  if (state.match?.profile && state.match.profile !== 'unknown') args.profile = state.match.profile;

  const action = ++state.action;
  const button = document.getElementById('btn-build');
  button.disabled = true;
  document.getElementById('btn-here').disabled = true;
  document.getElementById('output').setAttribute('aria-busy', 'true');
  show('<p class="loading" role="status">Checking generation options…</p>');
  const { status, body } = await API.buildCommand(args);
  if (action !== state.action) return;
  button.disabled = false;
  document.getElementById('btn-here').disabled = !state.match;
  document.getElementById('output').removeAttribute('aria-busy');
  if (status !== 200 || !body.command) {
    show(`<h3>No local command available</h3><p>${esc(body.reason || body.message || 'Try again in a moment.')}</p>
      <p><a href="/docs/how-to/convert-formats/">See generation and conversion options</a>.</p>`, status === 409 ? 'refused' : 'error');
    return;
  }
  show(`<h3>Build it on your machine</h3>
    <p>PseudoForge generates files on your machine with a local atomic engine.</p>
    <pre id="cmd">${esc(body.command)}</pre>
    <div class="actions">
      <button class="btn primary" id="copy">Copy command</button>
      <a class="btn" href="/docs/getting-started/installation/">Install PseudoForge</a>
    </div>`, 'ok');
  const copy = document.getElementById('copy');
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(body.command);
      copy.textContent = 'Copied';
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(document.getElementById('cmd'));
      selection.removeAllRanges();
      selection.addRange(range);
      API.notify('Clipboard unavailable. The command is selected for manual copying.');
    }
  });
}

function onCompare() {
  if (state.match) location.assign('/compare/?a=' + encodeURIComponent(state.match.id));
}

/* -- go -------------------------------------------------------------------- */
document.addEventListener('DOMContentLoaded', async () => {
  refillForElement(null);
  ['xc', 'family', 'rel', 'format'].forEach(id => {
    document.getElementById(id).addEventListener('change', () => {
      state.pickedProfile = null;
      refillForElement(state.element);
      refresh();
    });
  });
  await loadSelectors();
  drawTable();

  document.getElementById('btn-here').addEventListener('click', onHere);
  document.getElementById('btn-build').addEventListener('click', onBuild);
  document.getElementById('btn-compare').addEventListener('click', onCompare);
  loadRecentSection();
});

async function loadRecentSection() {
  const container = document.getElementById('recent-list');
  if (!container) return;
  const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  try {
    const res = await API.recent(5);
    if (res.status !== 200 || !Array.isArray(res.body)) throw new Error('Recent files unavailable');
    if (!res.body.length) {
      container.innerHTML = '<p class="quiet">No recently added files found.</p>';
      return;
    }
    const html = `
      <table class="recent-table" style="width: 100%; border-collapse: collapse; font-size: 0.88rem;">
        <thead>
          <tr style="text-align: left; border-bottom: 1px solid var(--line);">
            <th style="padding: 0.5rem 0.6rem; color: var(--muted); font-size: 0.82rem;">Date</th>
            <th style="padding: 0.5rem 0.6rem; color: var(--muted); font-size: 0.82rem;">File</th>
            <th style="padding: 0.5rem 0.6rem; color: var(--muted); font-size: 0.82rem;">Profile</th>
            <th style="padding: 0.5rem 0.6rem; color: var(--muted); font-size: 0.82rem;">Family</th>
            <th style="padding: 0.5rem 0.6rem; color: var(--muted); font-size: 0.82rem;">Functional</th>
            <th style="padding: 0.5rem 0.6rem; text-align: right; color: var(--muted); font-size: 0.82rem;">Actions</th>
          </tr>
        </thead>
        <tbody>
          ${res.body.map(f => `
            <tr style="border-bottom: 1px solid var(--line);">
              <td style="padding: 0.45rem 0.6rem; color: var(--muted); font-size: 0.82rem; white-space: nowrap;">${esc(f.date || '')}</td>
              <td style="padding: 0.45rem 0.6rem; font-family: var(--mono); font-weight: 500;">${esc(f.filename || '')}</td>
              <td style="padding: 0.45rem 0.6rem;">${esc(f.profile || '—')}</td>
              <td style="padding: 0.45rem 0.6rem;">${esc((f.family || '—').toUpperCase())}</td>
              <td style="padding: 0.45rem 0.6rem;">${esc((f.xc || '—').toUpperCase())}</td>
              <td style="padding: 0.45rem 0.6rem; text-align: right; white-space: nowrap;">
                ${f.id ? `<a href="/provenance/?id=${encodeURIComponent(f.id)}" class="btn-sm" style="margin-right: 0.35rem; display: inline-block; padding: 0.2rem 0.45rem; font-size: 0.78rem; text-decoration: none; border: 1px solid var(--line); border-radius: 4px; color: var(--fg);">Provenance</a>` : ''}
                ${f.id ? `<a href="${API.downloadUrl(f.id)}" class="btn-sm primary" style="display: inline-block; padding: 0.2rem 0.45rem; font-size: 0.78rem; text-decoration: none; background: var(--accent); color: #fff; border-radius: 4px;" download>Download</a>` : ''}
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `;
    container.innerHTML = html;
  } catch (err) {
    container.innerHTML = '<p class="quiet">Unable to load recent files.</p>';
  }
}


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
