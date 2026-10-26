/* ---------------------------------------------------------------------------
 * advise.js -- frontend controller for the Advisory System (/advise/)
 * ------------------------------------------------------------------------- */
'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const form = document.getElementById('advise-form');
  const elInput = document.getElementById('advise-el');
  const calcSelect = document.getElementById('advise-calc');
  const codeSelect = document.getElementById('advise-code');
  const accSelect = document.getElementById('advise-acc');
  const container = document.getElementById('advise-container');
  const resultsDiv = document.getElementById('advise-results');

  if (!form || !elInput || !container || !resultsDiv) return;

  // Copy helper
  async function copyText(text, btn) {
    let ok = false;
    try {
      await navigator.clipboard.writeText(text);
      ok = true;
    } catch (e) {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      try {
        ok = document.execCommand('copy');
      } catch (e2) {}
      document.body.removeChild(ta);
    }
    if (ok && btn) {
      const orig = btn.textContent;
      btn.textContent = 'Copied!';
      btn.disabled = true;
      setTimeout(() => {
        btn.textContent = orig;
        btn.disabled = false;
      }, 1500);
    }
  }

  function esc(s) {
    if (!s) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  async function runAdvise(el, calc, code, acc) {
    container.hidden = false;
    resultsDiv.innerHTML = '<div class="advise-loading">Evaluating pseudopotential candidates…</div>';

    const params = { element: el };
    if (calc) params.calculation = calc;
    if (code) params.code = code;
    if (acc)  params.accuracy = acc;

    // Update URL query parameters without reloading
    const u = new URL(window.location);
    u.searchParams.set('element', el);
    if (calc) u.searchParams.set('calculation', calc); else u.searchParams.delete('calculation');
    if (code) u.searchParams.set('code', code); else u.searchParams.delete('code');
    if (acc && acc !== 'balanced') u.searchParams.set('accuracy', acc); else u.searchParams.delete('accuracy');
    window.history.replaceState({}, '', u);

    const { status, body } = await API.advise(params);

    if (status !== 200 || body.error) {
      resultsDiv.innerHTML = `
        <div class="advise-error">
          <strong>Request failed (${status}):</strong> ${esc(body.message || body.error || 'Unknown error')}
        </div>`;
      return;
    }

    if (body.is_overview || body.overview) {
      renderOverview(body);
    } else {
      renderSingle(body);
    }
  }

  function renderSingle(data) {
    let html = `
      <div style="margin-bottom: 1.25rem;">
        <h2 style="margin: 0 0 0.35rem; color: var(--fg-strong);">
          ${esc(data.element)} (${esc(data.element_name)}) — ${esc(data.calculation)}
        </h2>
        <div style="font-size: 0.9rem; color: var(--muted);">
          Material class: <strong>${esc(data.material_class)}</strong>
          ${data.code ? ` · Target code: <strong>${esc(data.code.toUpperCase())}</strong>` : ''}
        </div>
      </div>`;

    if (!data.recommendations || data.recommendations.length === 0) {
      html += '<p>No recommendations found for this combination.</p>';
      resultsDiv.innerHTML = html;
      return;
    }

    data.recommendations.forEach((rec, idx) => {
      const isTop = idx === 0;
      const paragraphs = (rec.why || '')
        .split('\n\n')
        .map(p => `<p>${esc(p)}</p>`)
        .join('');

      let citationsHtml = '';
      if (rec.citations && rec.citations.length > 0) {
        const items = rec.citations.map(c => {
          const doiLink = c.doi
            ? ` — <a href="https://doi.org/${encodeURIComponent(c.doi)}" target="_blank" rel="noopener">doi:${esc(c.doi)}</a>`
            : '';
          return `<li><strong>${esc(c.name)}</strong> (${esc(c.kind)})${doiLink}</li>`;
        }).join('');
        citationsHtml = `
          <div class="advise-citations">
            <strong>Formal citations:</strong>
            <ul>${items}</ul>
          </div>`;
      }

      let caveatsHtml = '';
      if (rec.caveats && rec.caveats.length > 0) {
        const cavItems = rec.caveats.map(c => `<li>${esc(c)}</li>`).join('');
        caveatsHtml = `
          <div class="advise-caveats">
            <strong>Caveats:</strong>
            <ul style="margin: 0.3rem 0; padding-left: 1.25rem;">${cavItems}</ul>
          </div>`;
      }

      let cutoffHtml = '';
      if (rec.cutoff && rec.cutoff.value) {
        cutoffHtml = `
          <div class="advise-cutoff-box">
            ⚡ <strong>Recommended cutoff:</strong> ${esc(rec.cutoff.value)} ${esc(rec.cutoff.unit)}
            <span style="color: var(--muted); font-size: 0.82rem;">(${esc(rec.cutoff.source)})</span>
          </div>`;
      }

      html += `
        <div class="advise-rec-card ${isTop ? 'rank-1' : ''}">
          <div class="advise-rec-head">
            <span class="advise-rank-badge">#${rec.rank} ${isTop ? 'Top Recommendation' : 'Alternative'}</span>
            <span class="advise-pill">${esc(rec.profile_label || rec.profile)}</span>
            <span class="advise-pill">${esc((rec.family || '').toUpperCase())}</span>
            <span class="advise-pill">${esc(rec.xc)}</span>
            <span class="advise-pill">${esc(rec.engine_label || rec.engine)}</span>
            <span class="advise-pill">.${esc(rec.format)}</span>
            <span class="advise-score-pill">Score: ${rec.score}</span>
          </div>
          ${cutoffHtml}
          <div class="advise-why">${paragraphs}</div>
          ${caveatsHtml}
          ${citationsHtml}
          <div class="advise-cmd-box">
            <code>${esc(rec.cli_command)}</code>
            <button type="button" class="btn copy-btn" data-cmd="${esc(rec.cli_command)}">Copy</button>
          </div>
        </div>`;
    });

    if (data.avoid && data.avoid.length > 0) {
      const avoidItems = data.avoid.map(a => `<li><strong>${esc(a.what)}:</strong> ${esc(a.why)}</li>`).join('');
      html += `
        <div class="advise-avoid-panel">
          <h3>⚠️ What to avoid for this calculation</h3>
          <ul>${avoidItems}</ul>
        </div>`;
    }

    if (data.related && data.related.length > 0) {
      const relLinks = data.related.map(r => `
        <a class="advise-related-link" data-calc="${esc(r.label)}">${esc(r.label)}</a>
      `).join('');
      html += `
        <div class="advise-related-panel">
          <span>Related calculations for ${esc(data.element)}:</span> ${relLinks}
        </div>`;
    }

    resultsDiv.innerHTML = html;

    // Attach copy button listeners
    resultsDiv.querySelectorAll('.copy-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        copyText(btn.dataset.cmd, btn);
      });
    });

    // Attach related link listeners
    resultsDiv.querySelectorAll('.advise-related-link').forEach(link => {
      link.addEventListener('click', () => {
        calcSelect.value = link.dataset.calc;
        form.dispatchEvent(new Event('submit'));
      });
    });
  }

  function renderOverview(data) {
    let rows = '';
    const ov = data.overview || [];
    ov.forEach(item => {
      rows += `
        <tr>
          <td><strong>${esc(item.calculation)}</strong></td>
          <td>${esc(item.profile)}</td>
          <td>${esc((item.family || '').toUpperCase())}</td>
          <td>${esc(item.xc)}</td>
          <td>${item.cutoff_val ? esc(item.cutoff_val) + ' ' + esc(item.cutoff_unit) : '—'}</td>
          <td>
            <button type="button" class="btn advise-inspect-btn" data-calc="${esc(item.calculation)}" style="padding: 0.2rem 0.5rem; font-size: 0.8rem;">
              Inspect
            </button>
          </td>
        </tr>`;
    });

    resultsDiv.innerHTML = `
      <div style="margin-bottom: 1rem;">
        <h2 style="margin: 0 0 0.35rem; color: var(--fg-strong);">
          ${esc(data.element)} (${esc(data.element_name)}) — Overview
        </h2>
        <div style="font-size: 0.9rem; color: var(--muted);">
          Material class: <strong>${esc(data.material_class)}</strong>
        </div>
      </div>
      <table class="advise-overview-table">
        <thead>
          <tr>
            <th>Calculation</th>
            <th>Recommended Profile</th>
            <th>Family</th>
            <th>Functional</th>
            <th>Cutoff</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          ${rows}
        </tbody>
      </table>`;

    resultsDiv.querySelectorAll('.advise-inspect-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        calcSelect.value = btn.dataset.calc;
        form.dispatchEvent(new Event('submit'));
      });
    });
  }

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const el = elInput.value.trim();
    if (!el) {
      elInput.focus();
      return;
    }
    // Capitalize first letter
    const normEl = el.charAt(0).toUpperCase() + el.slice(1).toLowerCase();
    elInput.value = normEl;

    runAdvise(normEl, calcSelect.value, codeSelect.value, accSelect.value);
  });

  // Check URL query on initial load
  const q = new URLSearchParams(window.location.search);
  const qEl = q.get('element') || q.get('e');
  const qCalc = q.get('calculation') || q.get('calc');
  const qCode = q.get('code');
  const qAcc = q.get('accuracy') || q.get('acc');

  if (qEl) {
    elInput.value = qEl.charAt(0).toUpperCase() + qEl.slice(1).toLowerCase();
    if (qCalc !== null) calcSelect.value = qCalc;
    if (qCode) codeSelect.value = qCode;
    if (qAcc)  accSelect.value = qAcc;
    form.dispatchEvent(new Event('submit'));
  }
});
