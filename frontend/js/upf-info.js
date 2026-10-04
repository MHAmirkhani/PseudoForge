/* ---------------------------------------------------------------------------
 * upf-info.js -- client-side metadata extraction.
 *
 * Purpose
 * -------
 * Answer "what am I about to validate" without running the validator.  The
 * output is a small panel showing the file's own declarations: element,
 * functional, type, relativity, valence, cut-offs, and so on.  It does not
 * claim any of these are correct; that is what the server check is for.
 *
 * Formats
 * -------
 * UPF v2 (XML), UPF v1 (legacy text), PSML.  Fallback: show whatever
 * identifiable information is available -- the first line, the file size,
 * the detected magic -- so the panel is never empty for a file the reader
 * actually chose.
 *
 * Gzip
 * ----
 * The store keeps files as .UPF.gz.  A reader who drags the compressed file
 * in would see binary garbage if we did not decompress it.  Browsers that
 * support DecompressionStream get a transparent decompress; others fall
 * back to the raw read and the panel says so.
 * ------------------------------------------------------------------------- */
'use strict';

(function (global) {

  function pick(text, re) {
    const m = text.match(re);
    return m ? (m[1] || '').trim() : '';
  }

  function escapeHTML(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }

  /* Detect gzip by magic bytes; the extension is not enough because the
   * file may be gzipped under another name. */
  async function maybeGunzip(blob) {
    const head = new Uint8Array(await blob.slice(0, 2).arrayBuffer());
    const isGzip = head.length === 2 && head[0] === 0x1f && head[1] === 0x8b;
    if (!isGzip) return { text: await blob.text(), wasGzip: false, ok: true };
    if (typeof DecompressionStream === 'undefined') {
      return { text: '', wasGzip: true, ok: false,
               reason: 'this browser cannot decompress gzip; the validator on the server still can' };
    }
    try {
      const stream = blob.stream().pipeThrough(new DecompressionStream('gzip'));
      const text = await new Response(stream).text();
      return { text, wasGzip: true, ok: true };
    } catch (e) {
      return { text: '', wasGzip: true, ok: false, reason: e.message || 'decompression failed' };
    }
  }

  function parseUPF2(text) {
    if (!/<UPF\s+version=/i.test(text)) return null;
    const upfAttrs = pick(text, /<UPF\s+([^>]*)>/i);
    const version = pick(upfAttrs, /version="([^"]*)"/i);
    const header = pick(text, /<PP_HEADER\s+([^>]*?)\/?>/is);
    if (!header) return null;

    const get = (k) => {
      const m = header.match(new RegExp(k + '="([^"]*)"', 'i'));
      return m ? m[1] : '';
    };

    return {
      kind: 'UPF', version: version || '2',
      element: get('element'),
      functional: get('functional'),
      pseudoType: get('pseudo_type'),
      relativistic: get('relativistic'),
      zValence: get('z_valence'),
      isUltraSoft: get('is_ultrasoft'),
      isPAW: get('is_paw'),
      hasSO: get('has_so'),
      lMax: get('l_max'),
      numberOfProj: get('number_of_proj'),
      coreCorrection: get('core_correction'),
      generated: get('generated'),
      author: get('author'),
      date: get('date'),
      meshSize: pick(text, /mesh_size="(\d+)"/i),
      numberOfWfc: pick(text, /number_of_wfc="(\d+)"/i),
      hasNLCC: /<PP_NLCC\b/i.test(text) ? 'present' : 'absent',
      ecutwfc: pick(text, /\becutwfc="([^"]*)"/i),
      ecutrho: pick(text, /\becutrho="([^"]*)"/i),
    };
  }

  function parseUPF1(text) {
    if (!/<PP_HEADER>/i.test(text)) return null;
    if (/<UPF\s+version=/i.test(text)) return null;

    // UPF v1 puts the element on its own line: "   Si   Element".
    const element = pick(text, /^\s*([A-Z][a-z]?)\s+Element\b/m) ||
                    pick(text, /^\s*([A-Z][a-z]?)\s*$/m);
    const zValence = pick(text, /Z\s*valence\s*[:=]?\s*([\d.]+)/i);
    const functional = pick(text, /^\s*(PZ|PW91|PBE|PBEsol|BLYP|BP|VWN|WC|revPBE|SCAN|BLYP)\b/mi) ||
                       pick(text, /^\s*(PZ|PW91|PBE|PBEsol|BLYP|BP|VWN|WC|revPBE|SCAN)\b/mi);

    // The UPF v1 header is a fixed-column layout.  The most reliable reads
    // are line-based regexes; the rest is best-effort.
    return {
      kind: 'UPF', version: '1',
      element,
      functional,
      pseudoType: /Ultrasoft/i.test(text) ? 'US' : (/PAW/i.test(text) ? 'PAW' : 'NC'),
      relativistic: /scalar/i.test(text) ? 'scalar'
                   : (/full|spin-?orbit|dirac/i.test(text) ? 'full' : 'no'),
      zValence,
      isUltraSoft: /Ultrasoft/i.test(text) ? 'T' : 'F',
      isPAW: /PAW/i.test(text) ? 'T' : 'F',
      hasSO: /spin-?orbit/i.test(text) ? 'T' : '',
      lMax: pick(text, /l_max\s*[:=]\s*(\d+)/i),
      numberOfProj: '',
      coreCorrection: /NLCC|nonlinear core/i.test(text) ? 'T' : 'F',
      generated: pick(text, /Generated\s*[:=]?\s*(.+)/i),
      author: '',
      date: '',
      meshSize: pick(text, /mesh\s+size\s*[:=]?\s*(\d+)/i),
      numberOfWfc: '',
      hasNLCC: /NLCC|nonlinear core/i.test(text) ? 'present' : 'absent',
      ecutwfc: pick(text, /ecutwfc\s*[:=]?\s*([\d.]+)/i),
      ecutrho: pick(text, /ecutrho\s*[:=]?\s*([\d.]+)/i),
    };
  }

  function parsePSML(text) {
    if (!/<\s*psml/i.test(text)) return null;
    const header = pick(text, /<header>([\s\S]*?)<\/header>/i) || text;
    return {
      kind: 'PSML', version: '',
      element: pick(header, /<element[^>]*\bname="([^"]*)"/i) ||
               pick(header, /atomic-label="([^"]*)"/i),
      functional: pick(header, /<functional[^>]*\bname="([^"]*)"/i),
      pseudoType: 'NC',
      relativistic: pick(header, /relativity="([^"]*)"/i),
      zValence: pick(header, /z-pseudo="([^"]*)"/i) || pick(header, /z-valence="([^"]*)"/i),
      meshSize: pick(header, /<grid[^>]*\bnpts="([^"]*)"/i),
      hasNLCC: /<core-correction\b/i.test(text) ? 'present' : 'absent',
      numberOfProj: (text.match(/<projective-basis>/gi) || []).length + '',
      lMax: '',
      coreCorrection: /<core-correction\b/i.test(text) ? 'T' : 'F',
      isUltraSoft: 'F',
      isPAW: 'F',
      hasSO: /spin-orbit|has_so="T"/i.test(text) ? 'T' : '',
      generated: '', author: '', date: '',
      numberOfWfc: '', ecutwfc: '', ecutrho: '',
    };
  }

  function parseAny(text) {
    if (!text || text.length < 30) return null;
    return parseUPF2(text) || parseUPF1(text) || parsePSML(text);
  }

  const FIELD_LABELS = {
    element: 'Element',
    functional: 'Functional',
    pseudoType: 'Type',
    relativistic: 'Relativity',
    zValence: 'Valence electrons',
    coreCorrection: 'Nonlinear core',
    hasNLCC: 'NLCC block',
    lMax: 'l max',
    numberOfProj: 'Projectors',
    numberOfWfc: 'Wavefunctions',
    meshSize: 'Grid points',
    ecutwfc: 'Suggested cut-off',
    ecutrho: 'Suggested ρ cut-off',
    version: 'Format version',
    generated: 'Generated by',
    author: 'Author',
    date: 'Date',
  };

  function prettify(k, v) {
    if (v === '' || v == null) return '';
    if (k === 'relativistic') {
      return ({ scalar: 'scalar-relativistic', full: 'fully relativistic',
                no: 'non-relativistic' })[v] || v;
    }
    if (k === 'pseudoType') {
      return ({ NC: 'Norm-conserving', US: 'Ultrasoft', PAW: 'PAW' })[v] || v;
    }
    if (k === 'isUltraSoft' || k === 'isPAW' || k === 'coreCorrection') {
      return v === 'T' ? 'yes' : (v === 'F' ? 'no' : v);
    }
    if (k === 'ecutwfc' || k === 'ecutrho') {
      return v ? v + ' Ry' : '';
    }
    return v;
  }

  function render(info, host, meta) {
    meta = meta || {};

    if (!info) {
      // Fallback: show what we know, plus a short raw preview so the
      // reader is not left with a blank panel.
      const preview = (meta.preview || '').slice(0, 400);
      host.innerHTML =
        '<p class="quiet" style="margin:0 0 .75rem">' +
          escapeHTML(meta.reason || 'Could not identify this as a pseudopotential format.') +
        '</p>' +
        '<div class="info-header">' +
          '<span class="info-kind" style="background:#94a3b8">unknown</span>' +
          '<span class="info-file">' + escapeHTML(meta.name || '') +
          (meta.size != null ? ' — ' + Math.round(meta.size / 1024) + ' kB' : '') +
          '</span>' +
        '</div>' +
        (preview
          ? '<details class="raw-preview"><summary>Show first 400 characters</summary>' +
            '<pre>' + escapeHTML(preview) + '</pre></details>'
          : '');
      return;
    }

    // Element symbol square, if we found one.
    const sym = (info.element || '').trim();
    const symBox = sym
      ? `<span class="info-element" data-block="${(info.pseudoType === 'PAW' ? 'd' : 'p')}">${escapeHTML(sym)}</span>`
      : '';

    let html = `<div class="info-header">` +
      symBox +
      `<span class="info-kind">${escapeHTML(info.kind || 'unknown')}` +
      (info.version ? ` v${escapeHTML(info.version)}` : '') +
      `</span>` +
      `<span class="info-file">${escapeHTML(meta.name || '')}` +
      (meta.size != null ? ` — ${Math.round(meta.size / 1024)} kB` : '') +
      `</span>` +
      (meta.wasGzip ? `<span class="info-tag" title="file was gzip-compressed and decompressed in the browser">gzip</span>` : '') +
      `</div>`;

    const identity = ['element', 'functional', 'pseudoType', 'relativistic'];
    const physics  = ['zValence', 'coreCorrection', 'hasNLCC', 'lMax',
                      'numberOfProj', 'numberOfWfc'];
    const numerics = ['meshSize', 'ecutwfc', 'ecutrho', 'version', 'generated', 'author', 'date'];

    const card = (keys, heading) => {
      const rows = keys.map(k => {
        const val = prettify(k, info[k]);
        if (!val) return '';
        return `<div class="info-row"><dt>${FIELD_LABELS[k] || k}</dt>` +
               `<dd>${escapeHTML(String(val))}</dd></div>`;
      }).filter(Boolean).join('');
      if (!rows) return '';
      return `<div class="info-col"><h4>${heading}</h4><dl class="info-grid">${rows}</dl></div>`;
    };

    html += `<div class="info-sections">` +
      card(identity, 'Identity') +
      card(physics,  'Physics') +
      card(numerics, 'Numerics') +
      `</div>`;

    host.innerHTML = html;
  }

  /* Public: read a File and render into a host element.  Returns a promise
   * so the caller can chain on it. */
  /* The header in a UPF v2 file comes *after* PP_INFO, which in files from
   * some libraries is many hundreds of kilobytes of banner text.  Reading
   * only the first 256 kB missed it on a real Mn PAW file this session and
   * made the panel look broken.  We now read the whole file up to the
   * upload limit, then walk through it once looking for the fields we need.
   * The upload limit is 8 MB; a 4 MB read is generous and still fast. */
  const MAX_READ = 4 * 1024 * 1024;

  async function show(file, host) {
    host.innerHTML = '<p class="loading">Reading the file…</p>';
    try {
      const slice = file.slice(0, Math.min(file.size, MAX_READ));
      const { text, wasGzip, ok, reason } = await maybeGunzip(slice);
      if (!ok) {
        render(null, host, {
          name: file.name, size: file.size, wasGzip: true,
          reason: reason || 'could not decompress',
        });
        return;
      }
      if (text.length < 30) {
        render(null, host, {
          name: file.name, size: file.size, wasGzip,
          reason: 'The file is empty or unreadable as text.',
        });
        return;
      }
      const info = parseAny(text);
      render(info, host, {
        name: file.name, size: file.size, wasGzip,
        preview: text,
        reason: info
          ? ''
          : 'This file does not match a UPF, PSML, or PSP8 header this reader knows.',
      });
      requestAnimationFrame(() => {
        const panel = host.closest('section') || host;
        panel.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      });

      /* If the plots module is on the page, hand it the same text we just
       * parsed.  It renders whatever radial arrays the file contains, and
       * silently does nothing if none are found. */
      try {
        const plotsHost = document.getElementById('plots');
        if (window.UPFPlot && plotsHost) window.UPFPlot.render(file, text, plotsHost);
      } catch (e) {
        console.error('[upf-info] plots failed:', e);
      }
    } catch (err) {
      console.error('[upf-info] failed to read', file.name, err);
      host.innerHTML = '<p class="error">' + escapeHTML(err.message || err) + '</p>';
    }
  }

  global.UPFInfo = { parseAny, render, show, maybeGunzip };

})(window);
