/* ---------------------------------------------------------------------------
 * capabilities.js -- capability matrix renderer
 * ------------------------------------------------------------------------- */
'use strict';

const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

async function loadCapabilities() {
  const wrap = document.getElementById('capabilities-wrap');
  if (!wrap) return;

  try {
    const res = await api.capabilities();
    if (res.status !== 200 || !res.body) {
      wrap.innerHTML = `<p style="color: var(--danger);">Failed to load capabilities (${res.status}).</p>`;
      return;
    }

    const data = res.body;
    const tiers = [
      data.store_alone,
      data.cli_no_engines,
      data.cli_with_engines
    ].filter(Boolean);

    wrap.innerHTML = tiers.map(tier => `
      <div class="tier-card">
        <h2>${esc(tier.title || '')}</h2>
        <ul class="tier-list">
          ${(tier.items || []).map(item => `
            <li class="tier-item ${item.supported ? 'supported' : 'unsupported'}">
              <span class="icon">${item.supported ? '✅' : '❌'}</span>
              <span>${esc(item.text || '')}</span>
            </li>
          `).join('')}
        </ul>
      </div>
    `).join('');
  } catch (err) {
    wrap.innerHTML = `<p style="color: var(--danger);">Network error loading capabilities.</p>`;
  }
}

document.addEventListener('DOMContentLoaded', loadCapabilities);
