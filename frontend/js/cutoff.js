/* ---------------------------------------------------------------------------
 * cutoff.js -- client logic for /cutoff/ page
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  const btn = document.getElementById('btn-cutoff');
  const statusEl = document.getElementById('cut-status');
  const resEl = document.getElementById('cut-result');

  const rangeWfc = document.getElementById('range-wfc');
  const numWfc = document.getElementById('num-wfc');
  const rangeRho = document.getElementById('range-rho');
  const numRho = document.getElementById('num-rho');
  const valDual = document.getElementById('val-dual');
  const cutCmd = document.getElementById('cut-cmd');
  const copyBtn = document.getElementById('btn-copy-cmd');

  let currentElement = 'Fe';

  async function updateCommand() {
    const wfc = parseInt(numWfc.value, 10) || 0;
    const rho = parseInt(numRho.value, 10) || 0;
    if (wfc > 0 && rho > 0) {
      const ratio = (rho / wfc).toFixed(1);
      valDual.textContent = ratio + 'x';
      let fallback = `pseudoforge generate -e ${currentElement} --ecut ${wfc} --dual ${ratio}`;
      cutCmd.textContent = fallback;
      try {
        const u = new URL('/api/build-command', window.location.origin);
        u.searchParams.set('element', currentElement);
        u.searchParams.set('ecut', wfc);
        u.searchParams.set('dual', ratio);
        const r = await fetch(u.toString());
        if (r.ok) {
          const d = await r.json();
          if (d.command) cutCmd.textContent = d.command;
        }
      } catch (e) {}
    } else {
      valDual.textContent = '--';
      cutCmd.textContent = `pseudoforge generate -e ${currentElement}`;
    }
  }

  function setCutoffs(wfc, rho) {
    rangeWfc.value = wfc;
    numWfc.value = wfc;
    rangeRho.value = rho;
    numRho.value = rho;
    document.getElementById('val-wfc').textContent = wfc;
    document.getElementById('val-rho').textContent = rho;
    updateCommand();
  }

  // Dual sliders sync
  rangeWfc.addEventListener('input', () => {
    numWfc.value = rangeWfc.value;
    document.getElementById('val-wfc').textContent = rangeWfc.value;
    updateCommand();
  });
  numWfc.addEventListener('input', () => {
    rangeWfc.value = numWfc.value;
    document.getElementById('val-wfc').textContent = numWfc.value;
    updateCommand();
  });

  rangeRho.addEventListener('input', () => {
    numRho.value = rangeRho.value;
    document.getElementById('val-rho').textContent = rangeRho.value;
    updateCommand();
  });
  numRho.addEventListener('input', () => {
    rangeRho.value = numRho.value;
    document.getElementById('val-rho').textContent = numRho.value;
    updateCommand();
  });

  if (copyBtn) {
    copyBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(cutCmd.textContent).then(() => {
        copyBtn.textContent = 'Copied!';
        setTimeout(() => { copyBtn.textContent = 'Copy'; }, 1500);
      });
    });
  }

  async function fetchCutoff() {
    const el = (document.getElementById('cut-el').value || '').trim();
    const acc = document.getElementById('cut-acc').value;
    const xc = document.getElementById('cut-xc').value;

    if (!el) {
      statusEl.textContent = 'Please enter an element symbol.';
      return;
    }

    currentElement = el;
    statusEl.textContent = 'Looking up...';
    try {
      const resp = await fetch(`/api/cutoff?element=${encodeURIComponent(el)}&accuracy=${encodeURIComponent(acc)}&xc=${encodeURIComponent(xc)}`);
      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        statusEl.textContent = 'Error: ' + (err.message || resp.statusText);
        return;
      }

      const data = await resp.json();
      statusEl.textContent = '';
      resEl.hidden = false;

      document.getElementById('cut-title').textContent =
        `Recommended Cutoff: ${data.element} (${data.accuracy}, ${data.xc})`;
      document.getElementById('val-source').textContent = data.source || '-';
      document.getElementById('val-lib').textContent = data.library || '-';
      document.getElementById('val-prov').textContent = data.provenance || '-';

      setCutoffs(data.ecutwfc || 0, data.ecutrho || 0);
    } catch (e) {
      statusEl.textContent = 'Network error: ' + e.message;
    }
  }

  if (btn) {
    btn.addEventListener('click', fetchCutoff);
  }

  // Trigger default search on page load
  fetchCutoff();
})();
