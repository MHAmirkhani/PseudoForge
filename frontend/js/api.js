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

  async function get(path) {
    const r = await fetch(base + path, { headers: { Accept: 'application/json' } });
    const body = await r.json().catch(() => ({
      error: 'unreadable_response',
      message: 'The server did not return JSON.',
    }));
    return { status: r.status, body };
  }

  async function post(path, payload) {
    const r = await fetch(base + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const body = await r.json().catch(() => ({
      error: 'unreadable_response',
      message: 'The server did not return JSON.',
    }));
    return { status: r.status, body };
  }

  async function upload(path, file) {
    const form = new FormData();
    form.append('file', file);
    const r = await fetch(base + path, { method: 'POST', body: form });
    const body = await r.json().catch(() => ({
      error: 'unreadable_response',
      message: 'The server did not return JSON.',
    }));
    return { status: r.status, body };
  }

  return {
    health:   ()      => get('/health'),
    engines:  ()      => get('/engines'),
    engine:   (n)     => get('/engines/' + encodeURIComponent(n)),
    formats:  ()      => get('/formats'),
    profiles: ()      => get('/profiles'),
    xc:       ()      => get('/xc'),
    elements: ()      => get('/elements'),
    native:   ()      => get('/native'),
    nativeOne:(id)    => get('/native/' + encodeURIComponent(id)),
    convert:  (id, to)=> post('/convert', { id, to }),
    validate: (file)  => upload('/validate', file),
    generate: ()      => post('/generate', {}),
    downloadUrl: (id) => base + '/download/' + id,
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
