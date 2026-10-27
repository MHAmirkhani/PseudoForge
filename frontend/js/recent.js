/* ---------------------------------------------------------------------------
 * recent.js -- recent files viewer
 * ------------------------------------------------------------------------- */
'use strict';

const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

async function loadRecent(count) {
  const tbody = document.getElementById('recent-tbody');
  const stats = document.getElementById('recent-stats');
  tbody.innerHTML = '<tr><td colspan="7" class="loading" style="padding: 2rem; text-align: center;">Loading recent files…</td></tr>';

  try {
    const res = await api.recent(count);
    if (res.status !== 200 || !Array.isArray(res.body)) {
      tbody.innerHTML = `<tr><td colspan="7" style="padding: 2rem; text-align: center; color: var(--danger);">Failed to load recent files (${res.status}).</td></tr>`;
      return;
    }

    const items = res.body;
    stats.textContent = `Showing ${items.length} file${items.length === 1 ? '' : 's'}`;

    if (items.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" style="padding: 2rem; text-align: center; color: var(--muted);">No files found in the store.</td></tr>';
      return;
    }

    tbody.innerHTML = items.map(f => `
      <tr>
        <td style="color: var(--muted); font-size: 0.82rem; white-space: nowrap;">${esc(f.date || '—')}</td>
        <td style="font-family: var(--mono); font-weight: 500;">${esc(f.filename || '—')}</td>
        <td><a href="/elements/?element=${encodeURIComponent(f.element || '')}" style="color: var(--accent); font-weight: 600; text-decoration: none;">${esc(f.element || '—')}</a></td>
        <td>${esc(f.profile || '—')}</td>
        <td><span class="badge" style="text-transform: uppercase;">${esc(f.family || '—')}</span></td>
        <td><span class="badge" style="text-transform: uppercase;">${esc(f.xc || '—')}</span></td>
        <td style="text-align: right; white-space: nowrap;">
          ${f.id ? `<a href="/provenance/?id=${encodeURIComponent(f.id)}" class="btn-sm" style="margin-right: 0.35rem;">Provenance</a>` : ''}
          ${f.id ? `<a href="${api.downloadUrl(f.id)}" class="btn-sm primary" download>Download</a>` : ''}
        </td>
      </tr>
    `).join('');
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="7" style="padding: 2rem; text-align: center; color: var(--danger);">Network error loading recent files.</td></tr>`;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const select = document.getElementById('count-select');
  const count = parseInt(select.value, 10) || 25;
  loadRecent(count);

  select.addEventListener('change', () => {
    loadRecent(parseInt(select.value, 10) || 25);
  });
});
