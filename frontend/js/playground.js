/* ---------------------------------------------------------------------------
 * playground.js -- client controller for /playground/
 * ------------------------------------------------------------------------- */
'use strict';

(function () {
  const routeSelect = document.getElementById('route-select');
  const urlPreview = document.getElementById('url-preview');
  const pathBox = document.getElementById('path-params-box');
  const queryBox = document.getElementById('query-params-box');
  const bodyBox = document.getElementById('body-box');
  const reqBody = document.getElementById('req-body');
  const btnSend = document.getElementById('btn-send');
  const btnReset = document.getElementById('btn-reset');
  const respStatus = document.getElementById('resp-status');
  const respTime = document.getElementById('resp-time');
  const respBody = document.getElementById('resp-body');

  let routes = [];
  let currentRoute = null;

  const defaultTemplates = {
    '/api/advise': '{\n  "element": "Fe",\n  "calculation": "phonons"\n}',
    '/api/compare': '{\n  "a": "Fe.pbe-sp-van_ak.UPF",\n  "b": "Fe.pbe-spn-kjpaw_psl.1.0.0.UPF"\n}',
    '/api/convert': '{\n  "id": "Si.test.UPF",\n  "to": "psp8"\n}',
    '/api/validate': '<UPF version="2.0.1">\n  <PP_HEADER element="Fe"/>\n</UPF>',
    '/api/generate': '{\n  "element": "Fe"\n}'
  };

  const routeQueryParams = {
    '/api/advise': [
      { name: 'element', def: 'Fe', req: true },
      { name: 'calculation', def: 'phonons' },
      { name: 'code', def: 'qe' },
      { name: 'accuracy', def: 'balanced' }
    ],
    '/api/cutoff': [
      { name: 'element', def: 'Fe', req: true },
      { name: 'accuracy', def: 'precision' },
      { name: 'xc', def: 'PBE' }
    ],
    '/api/build-command': [
      { name: 'element', def: 'Fe', req: true },
      { name: 'family', def: 'paw' },
      { name: 'xc', def: 'pbe' },
      { name: 'engine', def: 'atompaw' },
      { name: 'relativity', def: 'full' }
    ],
    '/api/coverage': [
      { name: 'profile', def: '' },
      { name: 'element', def: 'Fe' }
    ],
    '/api/recent': [
      { name: 'count', def: '10' }
    ]
  };

  async function loadRoutes() {
    try {
      const resp = await fetch('/api/routes');
      if (!resp.ok) throw new Error('HTTP ' + resp.status);
      const data = await resp.json();
      routes = data.routes || [];

      routeSelect.innerHTML = '';
      routes.forEach((r, idx) => {
        const opt = document.createElement('option');
        opt.value = idx;
        opt.textContent = `[${r.method}] ${r.path} — ${r.summary}`;
        routeSelect.appendChild(opt);
      });

      if (routes.length > 0) {
        selectRoute(0);
      }
    } catch (e) {
      routeSelect.innerHTML = '<option value="">Failed to load /api/routes</option>';
      respBody.textContent = 'Error loading routes: ' + e.message;
    }
  }

  function selectRoute(idx) {
    currentRoute = routes[idx];
    if (!currentRoute) return;

    pathBox.innerHTML = '';
    pathBox.hidden = true;
    queryBox.innerHTML = '';
    bodyBox.hidden = true;

    // Check path parameters (e.g. :name, :symbol, :id)
    const pathSegments = currentRoute.path.split('/');
    const pathVars = [];
    pathSegments.forEach(seg => {
      if (seg.startsWith(':')) {
        pathVars.push(seg.replace(/:|\.\.\./g, ''));
      }
    });

    if (pathVars.length > 0) {
      pathBox.hidden = false;
      pathVars.forEach(v => {
        const div = document.createElement('div');
        div.className = 'play-field';
        div.innerHTML = `<label for="path-var-${v}">Path Param :${v}</label>
          <input type="text" id="path-var-${v}" value="${v === 'symbol' ? 'Fe' : v === 'name' ? 'oncvpsp' : 'Fe.test.UPF'}">`;
        pathBox.appendChild(div);
        div.querySelector('input').addEventListener('input', updateUrlPreview);
      });
    }

    if (currentRoute.method === 'POST') {
      bodyBox.hidden = false;
      reqBody.value = defaultTemplates[currentRoute.path] || '{}';
    } else {
      // Setup query fields if known
      const qp = routeQueryParams[currentRoute.path];
      if (qp) {
        qp.forEach(param => {
          const div = document.createElement('div');
          div.className = 'play-field';
          div.innerHTML = `<label for="qp-${param.name}">${param.name}${param.req ? ' (required)' : ''}</label>
            <input type="text" id="qp-${param.name}" value="${param.def || ''}">`;
          queryBox.appendChild(div);
          div.querySelector('input').addEventListener('input', updateUrlPreview);
        });
      }
    }

    updateUrlPreview();
  }

  function getCalculatedUrl() {
    if (!currentRoute) return '';
    let p = currentRoute.path;
    const pathInputs = pathBox.querySelectorAll('input');
    pathInputs.forEach(inp => {
      const v = inp.id.replace('path-var-', '');
      p = p.replace(new RegExp(':' + v + '(\\.\\.\\.)?'), encodeURIComponent(inp.value.trim()));
    });

    if (currentRoute.method === 'GET') {
      const qInps = queryBox.querySelectorAll('input');
      const params = new URLSearchParams();
      qInps.forEach(inp => {
        const val = inp.value.trim();
        if (val) {
          params.set(inp.id.replace('qp-', ''), val);
        }
      });
      const qStr = params.toString();
      if (qStr) p += '?' + qStr;
    }
    return p;
  }

  function updateUrlPreview() {
    if (!currentRoute) return;
    const url = getCalculatedUrl();
    urlPreview.textContent = `${currentRoute.method} ${url}`;
  }

  async function executeRequest() {
    if (!currentRoute) return;
    const url = getCalculatedUrl();
    respStatus.className = 'resp-badge';
    respStatus.textContent = 'Sending...';
    respBody.textContent = 'Loading...';

    const opts = {
      method: currentRoute.method,
      headers: {}
    };

    if (currentRoute.method === 'POST') {
      opts.body = reqBody.value;
      if (reqBody.value.trim().startsWith('{')) {
        opts.headers['Content-Type'] = 'application/json';
      }
    }

    const t0 = performance.now();
    try {
      const r = await fetch(url, opts);
      const ms = Math.round(performance.now() - t0);
      respTime.textContent = `${ms} ms`;

      if (r.status >= 200 && r.status < 300) {
        respStatus.className = 'resp-badge badge-2xx';
      } else if (r.status >= 400 && r.status < 500) {
        respStatus.className = 'resp-badge badge-4xx';
      } else {
        respStatus.className = 'resp-badge badge-5xx';
      }
      respStatus.textContent = `${r.status} ${r.statusText}`;

      const text = await r.text();
      try {
        const parsed = JSON.parse(text);
        respBody.textContent = JSON.stringify(parsed, null, 2);
      } catch (e) {
        respBody.textContent = text;
      }
    } catch (e) {
      const ms = Math.round(performance.now() - t0);
      respTime.textContent = `${ms} ms`;
      respStatus.className = 'resp-badge badge-5xx';
      respStatus.textContent = 'Network Error';
      respBody.textContent = e.message;
    }
  }

  routeSelect.addEventListener('change', () => {
    selectRoute(parseInt(routeSelect.value, 10));
  });

  btnSend.addEventListener('click', executeRequest);
  btnReset.addEventListener('click', () => {
    if (routeSelect.value !== '') selectRoute(parseInt(routeSelect.value, 10));
  });

  loadRoutes();
})();
