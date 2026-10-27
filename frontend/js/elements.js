/* ---------------------------------------------------------------------------
 * elements.js -- frontend logic for the element explorer
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  const form = document.getElementById('el-form');
  const input = document.getElementById('el-input');
  const resultDiv = document.getElementById('el-result');

  function esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  const FAM_NAMES = {
    nc: 'NC — norm-conserving',
    paw: 'PAW — projector augmented-wave',
    us: 'US — ultrasoft',
  };

  async function loadElement(symbol) {
    if (!symbol) return;
    input.value = symbol;
    resultDiv.innerHTML = '<p class="muted">Loading files for element <strong>' + esc(symbol) + '</strong>...</p>';

    try {
      const res = await API.element(symbol);
      if (res.status !== 200 || !res.body || res.body.error) {
        resultDiv.innerHTML =
          '<div class="el-error"><strong>Error:</strong> ' +
          esc((res.body && res.body.message) || 'Element not found.') +
          '</div>';
        return;
      }

      const d = res.body;
      let html = '<div class="el-card">';
      html += '<h2>' + esc(d.symbol) + ' (' + esc(d.name) + ', Z=' + esc(d.z) + ') — ' + esc(d.total_files) + ' files in the store</h2>';

      const families = d.families || {};
      for (const famKey of ['nc', 'paw', 'us']) {
        const files = families[famKey] || [];
        if (files.length === 0) continue;

        html += '<div class="el-family-section">';
        html += '<div class="el-family-title">' + esc(FAM_NAMES[famKey] || famKey.toUpperCase()) + '</div>';
        html += '<table class="el-table"><thead><tr>';
        html += '<th>Config</th><th>File</th><th>Engine</th><th>Size</th><th>Actions</th>';
        html += '</tr></thead><tbody>';

        for (const f of files) {
          const config = (f.xc || '') + ', ' + (f.relativity || '');
          html += '<tr>';
          html += '<td>' + esc(config) + '</td>';
          html += '<td><code>' + esc(f.file) + '</code></td>';
          html += '<td>' + esc(f.engine) + '</td>';
          html += '<td>' + esc(f.size_kb) + ' KB</td>';
          html += '<td>';
          html += '<a class="btn btn-sm" href="' + API.downloadUrl(f.id) + '">Download</a> ';
          html += '<a class="btn btn-sm" href="/provenance/?id=' + encodeURIComponent(f.id) + '">Provenance</a>';
          html += '</td>';
          html += '</tr>';
        }

        html += '</tbody></table></div>';
      }

      if (d.not_available && d.not_available.length > 0) {
        html += '<div class="el-unavail-box">';
        html += '<h3>Not available in the store:</h3>';
        for (const item of d.not_available) {
          html += '<div class="el-unavail-item">';
          html += '<div class="el-unavail-label">' + esc(item.profile) + ' ' + esc(item.family) + ' ' + esc(item.xc) + ' — generate with:</div>';
          html += '<div class="el-cmd-box"><code>' + esc(item.command) + '</code></div>';
          html += '</div>';
        }
        html += '</div>';
      }

      html += '</div>';
      resultDiv.innerHTML = html;
    } catch (e) {
      resultDiv.innerHTML = '<div class="el-error">Failed to load element details: ' + esc(e.message) + '</div>';
    }
  }

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const val = input.value.trim();
    if (val) {
      const url = new URL(window.location);
      url.searchParams.set('symbol', val);
      window.history.pushState({}, '', url);
      loadElement(val);
    }
  });

  // Check URL param or path
  const params = new URLSearchParams(window.location.search);
  const qSym = params.get('symbol') || params.get('s');
  if (qSym) {
    loadElement(qSym);
  } else {
    // Check if path has /elements/<symbol>
    const parts = window.location.pathname.split('/').filter(Boolean);
    if (parts.length >= 2 && parts[0] === 'elements') {
      loadElement(parts[1]);
    }
  }
})();
