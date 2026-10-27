/* ---------------------------------------------------------------------------
 * compare.js -- client logic for /compare/ page
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  let fileTextA = null;
  let fileTextB = null;

  // Pre-populate autocomplete from /api/native
  fetch('/api/native')
    .then(r => r.ok ? r.json() : [])
    .then(items => {
      const dlA = document.getElementById('native-list-a');
      const dlB = document.getElementById('native-list-b');
      if (!dlA || !dlB || !Array.isArray(items)) return;
      items.slice(0, 100).forEach(it => {
        const optA = document.createElement('option');
        optA.value = it.id;
        optA.textContent = `${it.element} (${it.engine}, ${it.xc})`;
        dlA.appendChild(optA);

        const optB = document.createElement('option');
        optB.value = it.id;
        optB.textContent = `${it.element} (${it.engine}, ${it.xc})`;
        dlB.appendChild(optB);
      });
    })
    .catch(() => {});

  const inpFileA = document.getElementById('file-a');
  if (inpFileA) {
    inpFileA.addEventListener('change', (e) => {
      const f = e.target.files[0];
      if (!f) return;
      document.getElementById('cmp-a').value = f.name;
      const r = new FileReader();
      r.onload = () => { fileTextA = r.result; };
      r.readAsText(f);
    });
  }

  const inpFileB = document.getElementById('file-b');
  if (inpFileB) {
    inpFileB.addEventListener('change', (e) => {
      const f = e.target.files[0];
      if (!f) return;
      document.getElementById('cmp-b').value = f.name;
      const r = new FileReader();
      r.onload = () => { fileTextB = r.result; };
      r.readAsText(f);
    });
  }

  const btn = document.getElementById('btn-compare');
  const statusEl = document.getElementById('cmp-status');
  const resEl = document.getElementById('cmp-result');

  if (btn) {
    btn.addEventListener('click', async () => {
      const a = (document.getElementById('cmp-a').value || '').trim();
      const b = (document.getElementById('cmp-b').value || '').trim();

      if (!a || !b) {
        statusEl.textContent = 'Please provide both File A and File B.';
        return;
      }

      statusEl.textContent = 'Comparing...';
      try {
        const resp = await fetch('/api/compare', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ a, b })
        });

        if (!resp.ok) {
          const err = await resp.json().catch(() => ({}));
          statusEl.textContent = 'Error: ' + (err.message || resp.statusText);
          return;
        }

        const data = await resp.json();
        statusEl.textContent = '';
        renderComparison(data);
      } catch (e) {
        statusEl.textContent = 'Network error: ' + e.message;
      }
    });
  }

  function pill(val, isChanged) {
    if (isChanged) {
      return `<span class="cmp-pill changed">${val}</span>`;
    }
    return `<span class="cmp-pill same">${val}</span>`;
  }

  function renderComparison(data) {
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
        data.warnings.map(w => `<li>${w}</li>`).join('') + '</ul>';
    } else {
      warnEl.hidden = true;
      warnEl.innerHTML = '';
    }

    // Plots overlay if UPF texts exist
    renderPlots(a.id, b.id);
  }

  async function renderPlots(idA, idB) {
    const box = document.getElementById('cmp-plot-box');
    const plots = document.getElementById('cmp-plots');
    if (!window.UPFPlot) return;

    if (!fileTextA && idA) {
      try {
        const r = await fetch(`/api/download/${idA}`);
        if (r.ok) fileTextA = await r.text();
      } catch (e) {}
    }
    if (!fileTextB && idB) {
      try {
        const r = await fetch(`/api/download/${idB}`);
        if (r.ok) fileTextB = await r.text();
      } catch (e) {}
    }

    if (!fileTextA || !fileTextB) {
      box.hidden = true;
      return;
    }

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
