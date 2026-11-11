/* ---------------------------------------------------------------------------
 * compare.js -- client logic for /compare/ page
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  let comparison = 0;
  API.native().then(({status, body}) => {
    if (status !== 200 || !Array.isArray(body)) return;
    for (const id of ['native-list-a', 'native-list-b']) {
      const list = document.getElementById(id);
      list.replaceChildren(...body.map(it => new Option(`${it.element} (${it.engine}, ${it.xc})`, it.id)));
    }
  });

  const search = new URLSearchParams(location.search);
  for (const side of ['a', 'b']) {
    document.getElementById('cmp-' + side).value = search.get(side) || '';
  }

  const btn = document.getElementById('btn-compare');
  const statusEl = document.getElementById('cmp-status');
  const resEl = document.getElementById('cmp-result');

  document.getElementById('cmp-form').addEventListener('submit', async e => {
    e.preventDefault();
    const a = document.getElementById('cmp-a').value.trim();
    const b = document.getElementById('cmp-b').value.trim();
    if (!a || !b) {
      statusEl.textContent = 'Enter both file IDs.';
      return;
    }

    const run = ++comparison;
    const plotBox = document.getElementById('cmp-plot-box');
    plotBox.hidden = true;
    resEl.hidden = true;
    btn.disabled = true;
    statusEl.classList.add('loading');
    statusEl.textContent = 'Comparing…';
    const { status, body } = await API.compare(a, b);
    btn.disabled = false;
    statusEl.classList.remove('loading');
    if (status !== 200) {
      statusEl.textContent = body.message || 'Could not compare these files.';
      API.notify(statusEl.textContent);
      return;
    }
    statusEl.textContent = '';
    renderComparison(body, run);
  });

  function pill(val, isChanged) {
    if (isChanged) {
      return `<span class="cmp-pill changed">${val}</span>`;
    }
    return `<span class="cmp-pill same">${val}</span>`;
  }

  function renderComparison(data, run) {
    resEl.hidden = false;

    // Diff table
    const d = data.diff || {};
    document.getElementById('diff-size-delta').innerHTML =
      (d.size_bytes_delta > 0 ? '+' : '') + (d.size_bytes_delta ?? 0) + ' bytes';
    document.getElementById('diff-sha256').innerHTML =
      pill(d.sha256_equal ? 'Identical' : 'Different', !d.sha256_equal);
    document.getElementById('diff-engine').innerHTML =
      pill(d.engine_changed ? 'Yes (changed)' : 'No', d.engine_changed);
    document.getElementById('diff-family').innerHTML =
      pill(d.family_changed ? 'Yes (changed)' : 'No', d.family_changed);
    document.getElementById('diff-xc').innerHTML =
      pill(d.xc_changed ? 'Yes (changed)' : 'No', d.xc_changed);
    document.getElementById('diff-relativity').innerHTML =
      pill(d.relativity_changed ? 'Yes (changed)' : 'No', d.relativity_changed);
    document.getElementById('diff-format').innerHTML =
      pill(d.format_changed ? 'Yes (changed)' : 'No', d.format_changed);

    // Cards
    const a = data.a || {};
    document.getElementById('card-a-title').textContent = a.id || 'File A';
    document.getElementById('card-a-id').textContent = a.id || '-';
    document.getElementById('card-a-el').textContent = a.element || '-';
    document.getElementById('card-a-eng').textContent = a.engine || '-';
    document.getElementById('card-a-xc').textContent = a.xc || '-';
    document.getElementById('card-a-cut').textContent =
      (a.cutoffs && a.cutoffs.sssp_precision) ? (a.cutoffs.sssp_precision + ' Ry') : 'none';

    const b = data.b || {};
    document.getElementById('card-b-title').textContent = b.id || 'File B';
    document.getElementById('card-b-id').textContent = b.id || '-';
    document.getElementById('card-b-el').textContent = b.element || '-';
    document.getElementById('card-b-eng').textContent = b.engine || '-';
    document.getElementById('card-b-xc').textContent = b.xc || '-';
    document.getElementById('card-b-cut').textContent =
      (b.cutoffs && b.cutoffs.sssp_precision) ? (b.cutoffs.sssp_precision + ' Ry') : 'none';

    // Warnings
    const warnEl = document.getElementById('cmp-warnings');
    if (data.warnings && data.warnings.length > 0) {
      warnEl.hidden = false;
      warnEl.innerHTML = '<strong>Warnings:</strong><ul style="margin:0.5rem 0 0 1rem;padding:0;">' +
        data.warnings.map(w => `<li>${String(w).replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]))}</li>`).join('') + '</ul>';
    } else {
      warnEl.hidden = true;
      warnEl.innerHTML = '';
    }

    // Plots overlay if UPF texts exist
    if (a.format === "upf" && b.format === "upf") renderPlots(a.id, b.id, run);
  }

  async function renderPlots(idA, idB, run) {
    const box = document.getElementById('cmp-plot-box');
    const plots = document.getElementById('cmp-plots');
    if (!window.UPFPlot) return;

    const read = id => fetch(API.downloadUrl(id))
      .then(response => response.ok ? response.text() : null).catch(() => null);
    const [fileTextA, fileTextB] = await Promise.all([read(idA), read(idB)]);
    if (run !== comparison || !fileTextA || !fileTextB) return;

    const arrA = UPFPlot.parseArrays(fileTextA);
    const arrB = UPFPlot.parseArrays(fileTextB);

    if (!arrA || !arrB || !arrA.r || !arrB.r) {
      box.hidden = true;
      return;
    }

    box.hidden = false;
    let html = '<div class="plot-grid">';

    // Overlaid local potential
    if (arrA.vloc && arrB.vloc) {
      const rmax = Math.min(6, Math.max(arrA.r[arrA.r.length - 1], arrB.r[arrB.r.length - 1]));
      html += '<div class="plot-card">' + UPFPlot.chart({
        title: 'V_loc comparison',
        xlabel: 'r (bohr)',
        ylabel: 'V_loc (Ry)',
        xmax: rmax,
        series: [
          { x: arrA.r, y: arrA.vloc, color: '#3b82f6', label: (idA || 'A') + ' V_loc' },
          { x: arrB.r, y: arrB.vloc, color: '#ef4444', label: (idB || 'B') + ' V_loc' }
        ]
      }) + '</div>';
    }

    // Valence density
    if (arrA.rho && arrB.rho) {
      const rmax = Math.min(6, Math.max(arrA.r[arrA.r.length - 1], arrB.r[arrB.r.length - 1]));
      html += '<div class="plot-card">' + UPFPlot.chart({
        title: 'Valence density comparison',
        xlabel: 'r (bohr)',
        ylabel: 'rho(r) (e/bohr^3)',
        xmax: rmax,
        series: [
          { x: arrA.r, y: arrA.rho, color: '#3b82f6', label: (idA || 'A') + ' rho' },
          { x: arrB.r, y: arrB.rho, color: '#ef4444', label: (idB || 'B') + ' rho' }
        ]
      }) + '</div>';
    }

    html += '</div>';
    plots.innerHTML = html;
  }
})();
