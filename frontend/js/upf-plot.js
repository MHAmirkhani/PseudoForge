/* ---------------------------------------------------------------------------
 * upf-plot.js -- radial plots for a UPF file.
 *
 * What gets drawn and why
 * -----------------------
 * A UPF contains, in addition to the header fields the info panel shows,
 * three radial arrays that describe the pseudopotential physically:
 *
 *   PP_LOCAL      V_loc(r)      the local potential, in Ry
 *   PP_PSWFC/CHI  u_l(r)        pseudo-wavefunctions, one per l channel
 *   PP_RHOATOM    rho(r)        valence density
 *
 * These are what a reader looks at to decide whether the file is what they
 * wanted.  The header says "PAW, PBE, scalar" and could be true of many
 * files; the shape of V_loc and the node count of each u_l is specific to
 * this one.
 *
 * Drawing
 * -------
 * Plain SVG, no library.  Colours come from CSS custom properties, so the
 * plots follow the theme like everything else on the page.  Each plot is
 * a self-contained <svg> so the layout is just a grid.
 *
 * Robustness
 * ----------
 * Files from different engines differ in small ways: some have all three
 * arrays, some are missing PP_PSWFC, some put the wavefunction label in an
 * attribute and some in a comment.  The parser is tolerant: a missing
 * array means a missing plot, not an error.  If nothing parses, the whole
 * panel shows a single line saying so.
 * ------------------------------------------------------------------------- */
'use strict';

(function (global) {

  const COLOR = {
    s: '#3b82f6',
    p: '#ef4444',
    d: '#10b981',
    f: '#a855f7',
    vloc: '#64748b',
    rho: '#f59e0b',
  };

  /* Whitespace-separated numbers inside <TAG>...</TAG>. */
  function block(text, tag) {
    const re = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
    const m = text.match(re);
    if (!m) return null;
    const nums = m[1].trim().split(/\s+/).map(Number).filter(Number.isFinite);
    return nums.length ? nums : null;
  }

  /* Every <PP_CHI ... l="N">...</PP_CHI> in the file.  UPF v2 wraps each
   * one in <PP_CHI.k> with the metadata, and the inner tag has the data. */
  function wavefunctions(text) {
    const out = [];
    const re = /<PP_CHI\b[^>]*\bl="(\d+)"[^>]*>([\s\S]*?)<\/PP_CHI>/gi;
    let m;
    while ((m = re.exec(text)) !== null) {
      const l = parseInt(m[1], 10);
      const data = m[2].trim().split(/\s+/).map(Number).filter(Number.isFinite);
      if (data.length) out.push({ l, data });
    }
    return out;
  }

  function parseArrays(text) {
    const r = block(text, 'PP_R');
    if (!r) return null;
    return {
      r,
      vloc: block(text, 'PP_LOCAL'),
      rho:  block(text, 'PP_RHOATOM'),
      wfc:  wavefunctions(text),
    };
  }

  /* Take at most max points, evenly spaced, always keeping the last one. */
  function subsample(x, y, max) {
    max = max || 500;
    if (x.length <= max) return { x, y };
    const step = Math.ceil(x.length / max);
    const sx = [], sy = [];
    for (let i = 0; i < x.length; i += step) { sx.push(x[i]); sy.push(y[i]); }
    if (sx[sx.length - 1] !== x[x.length - 1]) {
      sx.push(x[x.length - 1]);
      sy.push(y[y.length - 1]);
    }
    return { x: sx, y: sy };
  }

  function niceTicks(lo, hi, n) {
    const range = hi - lo;
    if (range <= 0) return [lo];
    const raw = range / n;
    const mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const norm = raw / mag;
    const step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
    const out = [];
    for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(v);
    return out;
  }

  let chartCounter = 0;

  function chart(opts) {
    const clipId = 'plot-clip-' + (chartCounter++);
    const W = 380, H = 240;
    const M = { t: 34, r: 14, b: 40, l: 56 };
    const IW = W - M.l - M.r;
    const IH = H - M.t - M.b;

    let xmax = opts.xmax || 0;
    if (!xmax) for (const s of opts.series) for (const v of s.x) if (v > xmax) xmax = v;

    /* Use 1st and 99th percentiles as the y-range instead of min and max.
     * A single outlier near the nucleus -- the potential at r=0, for
     * example -- otherwise squashes the entire visible curve into a flat
     * line at the top of the plot. */
    let ymin = Infinity, ymax = -Infinity;
    const allY = [];
    for (const s of opts.series) for (const v of s.y) if (Number.isFinite(v)) allY.push(v);
    if (allY.length) {
      allY.sort((a, b) => a - b);
      const lo = allY[Math.floor(allY.length * 0.01)] ?? allY[0];
      const hi = allY[Math.floor(allY.length * 0.99)] ?? allY[allY.length - 1];
      ymin = Math.min(lo, 0);
      ymax = Math.max(hi, 0);
    }
    const pad = (ymax - ymin) * 0.08 || 1;
    ymin -= pad; ymax += pad;

    const xToPx = (x) => M.l + (x / xmax) * IW;
    const yToPx = (y) => M.t + IH - ((y - ymin) / (ymax - ymin)) * IH;

    const xTicks = niceTicks(0, xmax, 5);
    const yTicks = niceTicks(ymin, ymax, 5);

    let svg = `<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" class="plot-svg">`;
    svg += `<defs><clipPath id="${clipId}"><rect x="${M.l}" y="${M.t}" width="${IW}" height="${IH}"/></clipPath></defs>`;
    svg += `<text x="${W/2}" y="18" text-anchor="middle" class="plot-title">${esc(opts.title)}</text>`;
    svg += `<rect x="${M.l}" y="${M.t}" width="${IW}" height="${IH}" class="plot-frame"/>`;

    for (const xt of xTicks) {
      const px = xToPx(xt);
      svg += `<line x1="${px}" y1="${M.t}" x2="${px}" y2="${M.t+IH}" class="plot-grid"/>`;
      svg += `<text x="${px}" y="${M.t+IH+14}" text-anchor="middle" class="plot-tick">${xt.toFixed(xt >= 10 ? 0 : 1)}</text>`;
    }
    for (const yt of yTicks) {
      const py = yToPx(yt);
      svg += `<line x1="${M.l}" y1="${py}" x2="${M.l+IW}" y2="${py}" class="plot-grid"/>`;
      const label = Math.abs(yt) >= 100 ? yt.toFixed(0)
                  : Math.abs(yt) >= 1   ? yt.toFixed(2)
                  : yt.toFixed(3);
      svg += `<text x="${M.l-6}" y="${py+4}" text-anchor="end" class="plot-tick">${label}</text>`;
    }

    svg += `<text x="${M.l+IW/2}" y="${H-6}" text-anchor="middle" class="plot-axis-label">${esc(opts.xlabel)}</text>`;
    svg += `<text transform="translate(14 ${M.t+IH/2}) rotate(-90)" text-anchor="middle" class="plot-axis-label">${esc(opts.ylabel)}</text>`;

    svg += `<g clip-path="url(#${clipId})">`;
    for (const s of opts.series) {
      const sub = subsample(s.x, s.y, 500);
      let path = '';
      for (let i = 0; i < sub.x.length; i++) {
        const px = xToPx(sub.x[i]), py = yToPx(sub.y[i]);
        if (!Number.isFinite(px) || !Number.isFinite(py)) continue;
        path += (path ? ' L ' : 'M ') + px.toFixed(2) + ' ' + py.toFixed(2);
      }
      svg += `<path d="${path}" fill="none" stroke="${s.color}" class="plot-line"/>`;
    }
    svg += '</g>';

    if (opts.series.length > 1 || opts.series[0].label) {
      let lx = M.l + 8;
      for (const s of opts.series) {
        if (!s.label) continue;
        svg += `<line x1="${lx}" y1="${M.t+10}" x2="${lx+16}" y2="${M.t+10}" stroke="${s.color}" stroke-width="2"/>`;
        svg += `<text x="${lx+20}" y="${M.t+14}" class="plot-legend-text">${esc(s.label)}</text>`;
        lx += 20 + 8 * s.label.length + 18;
      }
    }

    svg += '</svg>';
    return svg;
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }

  /* Render everything we found into the given host element.  Clipping the
   * x-range at 6 bohr keeps the interesting region readable; V_loc tails
   * off as -2Z/r and would otherwise squash the plot. */
  function render(file, text, host) {
    const data = parseArrays(text);
    if (!data) {
      host.innerHTML = '<p class="quiet" style="margin:0">This file does not contain the radial arrays used for plots.</p>';
      return;
    }

    /* Clip the x-range at 6 bohr, or wherever the radial grid ends if it is
     * shorter.  Beyond that the interesting structure is over and the tail
     * is just flattening out. */
    const rmax = Math.min(data.r[data.r.length - 1], 6);

    /* Filter arrays to the same window so V_loc, wavefunctions, and the
     * density are all plotted on the same abscissa.  Without this a file
     * whose grid extends to 100 bohr would have its wavefunctions appear
     * to be plotted at the wrong place relative to the potential. */
    function trim(arr) {
      const out = [];
      for (let i = 0; i < data.r.length && i < arr.length; i++) {
        if (data.r[i] > rmax) break;
        out.push(arr[i]);
      }
      return out;
    }
    const rPlot = trim(data.r);

    let html = '<div class="plot-grid">';

    if (data.vloc && data.vloc.length === data.r.length) {
      html += '<div class="plot-card">' + chart({
        title: 'Local potential',
        xlabel: 'r (bohr)',
        ylabel: 'V_loc (Ry)',
        xmax: rmax,
        series: [{ x: rPlot, y: trim(data.vloc), color: COLOR.vloc, label: 'V_loc' }],
      }) + '</div>';
    }

    if (data.wfc && data.wfc.length) {
      const ls = ['s', 'p', 'd', 'f', 'g', 'h'];
      const series = data.wfc.map(w => ({
        x: rPlot,
        y: trim(w.data),
        color: COLOR[ls[w.l]] || '#888',
        label: ls[w.l] || ('l=' + w.l),
      }));
      html += '<div class="plot-card">' + chart({
        title: 'Pseudo-wavefunctions',
        xlabel: 'r (bohr)',
        ylabel: 'u(r)  (arb.)',
        xmax: rmax,
        series,
      }) + '</div>';
    }

    if (data.rho && data.rho.length === data.r.length) {
      html += '<div class="plot-card">' + chart({
        title: 'Valence density',
        xlabel: 'r (bohr)',
        ylabel: 'rho(r) (e/bohr^3)',
        xmax: rmax,
        series: [{ x: rPlot, y: trim(data.rho), color: COLOR.rho, label: 'rho' }],
      }) + '</div>';
    }

    html += '</div>';

    if (html === '<div class="plot-grid"></div>') {
      host.innerHTML = '<p class="quiet" style="margin:0">No plottable arrays were found in this file.</p>';
      return;
    }
    host.innerHTML = html;
  }

  global.UPFPlot = { parseArrays, render, chart };
})(window);
