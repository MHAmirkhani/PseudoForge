/* ---------------------------------------------------------------------------
 * coverage.js -- interactive coverage matrix viewer
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  const elInput = document.getElementById('cov-el');
  const profSelect = document.getElementById('cov-prof');
  const container = document.getElementById('cov-container');

  function esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  async function loadCoverage() {
    container.innerHTML = '<p class="muted">Loading coverage matrix...</p>';
    const params = {};
    if (elInput.value.trim()) params.element = elInput.value.trim();
    if (profSelect.value) params.profile = profSelect.value;

    try {
      const res = await API.coverage(params);
      if (res.status !== 200 || !Array.isArray(res.body)) {
        container.innerHTML = '<div class="warn">Could not load coverage data.</div>';
        return;
      }

      const rows = res.body;
      if (rows.length === 0) {
        container.innerHTML = '<p class="muted">No coverage data matched your filter.</p>';
        return;
      }

      // Collect distinct profiles and elements preserving order
      const profs = [];
      const els = [];
      const map = {};

      for (const r of rows) {
        if (!profs.includes(r.profile)) profs.push(r.profile);
        if (!els.includes(r.element)) els.push(r.element);
        map[r.element + '|' + r.profile] = r;
      }

      let html = '<div class="cov-table-wrap"><table class="cov-table">';
      html += '<thead><tr><th>Element</th>';
      for (const p of profs) {
        html += '<th>' + esc(p) + '</th>';
      }
      html += '</tr></thead><tbody>';

      for (const e of els) {
        html += '<tr>';
        html += '<td><strong><a href="/elements/?symbol=' + encodeURIComponent(e) + '">' + esc(e) + '</a></strong></td>';
        for (const p of profs) {
          const item = map[e + '|' + p];
          const label = item ? item.label : '⚪ —';
          html += '<td><button type="button" class="cov-cell-btn" onclick="location.href=\'/elements/?symbol=' + encodeURIComponent(e) + '\'">' + esc(label) + '</button></td>';
        }
        html += '</tr>';
      }

      html += '</tbody></table></div>';
      container.innerHTML = html;
    } catch (err) {
      container.innerHTML = '<div class="warn">Failed to load coverage: ' + esc(err.message) + '</div>';
    }
  }

  elInput.addEventListener('input', () => {
    clearTimeout(elInput._timer);
    elInput._timer = setTimeout(loadCoverage, 300);
  });

  profSelect.addEventListener('change', loadCoverage);

  loadCoverage();
})();
