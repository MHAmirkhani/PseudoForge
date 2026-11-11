/* ---------------------------------------------------------------------------
 * api.js -- the only place the frontend talks to the server.
 *
 * Every shape here comes from lib/http.sh. Nothing is computed client-side
 * that the core could answer: if the browser decided whether a conversion was
 * possible, that judgement would exist in two places and one of them would go
 * stale.
 * ------------------------------------------------------------------------- */
'use strict';

const API = (() => {
  const base = '/api';

  let lastNotice = '';
  let noticeTimer;
  function notify(message) {
    if (message === lastNotice) return;
    lastNotice = message;
    let toast = document.getElementById('pf-toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'pf-toast';
      toast.className = 'toast';
      toast.setAttribute('role', 'status');
      document.body.appendChild(toast);
    }
    toast.hidden = false;
    toast.textContent = message;
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => {
      toast.hidden = true;
      lastNotice = '';
    }, 6000);
  }

  async function request(path, options = {}) {
    try {
      const r = await fetch(base + path, { ...options, signal: AbortSignal.timeout(125000) });
      const body = await r.json().catch(() => null);
      if (body !== null && typeof body === 'object') return { status: r.status, body };
      notify('The server returned an unreadable response.');
      return { status: r.ok ? 502 : r.status, body: {
        error: 'unreadable_response', message: 'The server did not return readable JSON.',
      } };
    } catch {
      const message = 'Could not reach PseudoForge. Check your connection and try again.';
      notify(message);
      return { status: 0, body: { error: 'network_error', message } };
    }
  }

  const get = path => request(path, { headers: { Accept: 'application/json' } });
  const post = (path, payload) => request(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  function upload(path, file) {
    const body = new FormData();
    body.append('file', file);
    return request(path, { method: 'POST', body });
  }

  return {
    notify,
    buildCommand: params => get('/build-command?' + new URLSearchParams(params)),
    health:   ()      => get('/health'),
    engines:  ()      => get('/engines'),
    engine:   (n)     => get('/engines/' + encodeURIComponent(n)),
    formats:  ()      => get('/formats'),
    profiles: ()      => get('/profiles'),
    xc:       ()      => get('/xc'),
    elements: ()      => get('/elements'),
    element:  (sym)   => get('/elements/' + encodeURIComponent(sym)),
    native:   ()      => get('/native'),
    nativeOne:(id)    => get('/native/' + encodeURIComponent(id)),
    convert:  (id, to)=> post('/convert', { id, to }),
    validate: (file)  => upload('/validate', file),
    generate: ()      => post('/generate', {}),
    advise:   (params)=> get('/advise?' + new URLSearchParams(params).toString()),
    provenance: (id)  => get('/provenance/' + encodeURIComponent(id)),
    coverage:   (params) => get('/coverage' + (params ? '?' + new URLSearchParams(params).toString() : '')),
    compare: (a, b) => post('/compare', { a, b }),
    recent:     (count)  => get('/recent' + (count ? '?count=' + encodeURIComponent(count) : '')),
    capabilities: ()     => get('/capabilities'),
    downloadUrl: (id) => base + '/download/' + encodeURIComponent(id),
  };
})();

/* The official copy, for "download from the authors". These are the upstream
 * projects' own distribution points; PseudoForge mirrors nothing it cannot
 * attribute. */
const OFFICIAL = {
  'psl-high':   'https://dalcorso.github.io/pslibrary/',
  'psl-low':    'https://dalcorso.github.io/pslibrary/',
  'psl-031':    'https://dalcorso.github.io/pslibrary/',
  'psl-alt':    'https://dalcorso.github.io/pslibrary/',
  'psl-tot':    'https://dalcorso.github.io/pslibrary/',
  sg15:         'http://www.quantum-simulation.org/potentials/sg15_oncv/',
  pseudodojo:   'http://www.pseudo-dojo.org/',
  gbrv:         'https://www.physics.rutgers.edu/gbrv/',
  sssp:         'https://www.materialscloud.org/discover/sssp/table/efficiency',
  'cp2k-gth':   'https://github.com/cp2k/cp2k-data',
  adpack:       'http://www.openmx-square.org/',
};
