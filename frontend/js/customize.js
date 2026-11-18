'use strict';

document.addEventListener('DOMContentLoaded', async () => {
  const host = document.getElementById('customize-app');
  const labels = {
    config: ['Reference configuration', 'text', '[Ne] 3s2 3p2'],
    core_hole: ['Core-hole orbital', 'text', '1s'],
    zed: ['Nuclear charge', 'text', ''], zval: ['Valence charge', 'text', ''],
    nlcc: ['Nonlinear core correction', 'select', ['', 'on', 'off']],
    rcore: ['Core radius (bohr)', 'text', ''], rho0: ['Core density parameter', 'text', ''],
    lloc: ['Local channel (ld1: −1; ONCVPSP: 4 for independent local)', 'text', ''],
    rcloc: ['Local radius (bohr)', 'text', ''],
    channel_radii: ['Channel radii (bohr; space-separated)', 'text', 's:1.7 p:1.8'],
    rcut_scale: ['Scale all cutoff radii', 'text', '1.0'],
    extra_projectors: ['Extra projectors (space-separated)', 'text', '3D:0.5'],
    which_augfun: ['Augmentation shape', 'select', ['', 'AE', 'PSQ', 'BESSEL', 'GAUSS', 'BG']],
    rmatch_augfun: ['Augmentation matching radius (bohr)', 'text', ''],
    nc_form: ['Norm-conserving representation', 'select', ['', 'separable', 'semilocal']],
    beta: ['SCF mixing', 'text', ''], tr2: ['SCF convergence threshold', 'text', ''],
    xmin: ['Radial grid xmin', 'text', ''], dx: ['Radial grid spacing', 'text', ''],
    rmax: ['Radial grid extent (bohr)', 'text', ''],
    lsd: ['Spin-polarised reference atom', 'checkbox', ''],
    gipaw: ['GIPAW reconstruction', 'checkbox', ''],
  };
  const make = (tag, text, className) => {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  };
  host.replaceChildren(make('p', 'Loading engine controls…', 'loading'));
  const [engines, profiles, functionals] = await Promise.all([API.engines(), API.profiles(), API.xc()]);
  if ([engines, profiles, functionals].some(result => result.status !== 200 || !Array.isArray(result.body))) {
    host.replaceChildren(make('p', 'Controls could not be loaded. Reload to try again.', 'error'));
    return;
  }
  host.replaceChildren();
  const form = make('form');
  const fields = make('div', '', 'custom-fields');
  const select = (key, title, options) => {
    const label = make('label', title);
    const input = make('select'); input.id = key; input.name = key;
    for (const option of options) {
      const node = make('option', option.label || option.id); node.value = option.id;
      input.append(node);
    }
    label.append(input); fields.append(label); return input;
  };
  const elementLabel = make('label', 'Element');
  const element = make('input'); element.id = 'custom-element'; element.value = 'Si';
  element.required = true; element.pattern = '[A-Z][a-z]?'; elementLabel.append(element); fields.append(elementLabel);
  const engine = select('custom-engine', 'Generator', engines.body);
  const family = select('custom-family', 'Formulation', [{id: 'nc'}, {id: 'us'}, {id: 'paw'}]);
  const xc = select('custom-xc', 'Functional', functionals.body.filter(item => item.status !== 'proxy'));
  xc.value = 'pbe';
  const relativity = select('custom-rel', 'Relativity', [{id: 'scalar'}, {id: 'nonrel'}, {id: 'full'}]);
  const profile = select('custom-profile', 'Parameter source', profiles.body.filter(item => item.generatable));
  profile.value = 'psl-high';
  form.append(fields);
  const hint = make('p', 'Generation runs on your computer. This page builds a validated command; final deck checks happen locally.', 'hint');
  form.append(hint);
  const controls = make('div', '', 'custom-fields'); controls.id = 'physics-controls'; form.append(controls);
  const inputByKey = new Map();
  const result = make('div'); result.id = 'custom-result'; result.setAttribute('aria-live', 'polite');
  const submit = make('button', 'Build command', 'btn primary'); submit.type = 'submit';
  form.append(submit); host.append(form, result);
  let revision = 0;
  let previousEngine = '';
  const invalidate = () => { revision++; result.replaceChildren(); };
  const update = () => {
    invalidate(); controls.replaceChildren(); inputByKey.clear();
    const selected = engines.body.find(item => item.id === engine.value);
    if (engine.value !== previousEngine) {
      const defaults = {ld1: 'psl-high', oncvpsp: 'sg15', opium: 'opium', uspp: 'gbrv',
        fhi98pp: 'fhi', atompaw: 'atompaw', ape: 'pseudoforge-auto', adpack: 'adpack', gth: 'cp2k-gth'};
      profile.value = defaults[engine.value] || 'pseudoforge-auto'; previousEngine = engine.value;
    }
    for (const option of family.options) option.disabled = !selected.families.split(' ').includes(option.value);
    if (family.selectedOptions[0].disabled) family.value = Array.from(family.options).find(option => !option.disabled).value;
    for (const control of selected.controls || []) {
      if (!labels[control.key] || control.mode === 'unsupported') continue;
      if (family.value === 'nc' && ['which_augfun', 'rmatch_augfun'].includes(control.key)) continue;
      if (family.value !== 'nc' && control.key === 'nc_form') continue;
      const [text, type, sample] = labels[control.key];
      const label = make('label', text);
      const input = make(type === 'select' ? 'select' : 'input');
      input.id = 'control-' + control.key;
      if (type === 'select') {
        for (const value of sample) {
          const option = make('option', value || 'Keep source setting'); option.value = value; input.append(option);
        }
      } else { input.type = type; if (sample) input.placeholder = sample; }
      if (control.mode === 'construction') label.append(make('small', 'Applies to constructed inputs. Published decks require editing their native input.', 'hint'));
      label.append(input); controls.append(label); inputByKey.set(control.key, input);
    }
  };
  engine.addEventListener('change', update); family.addEventListener('change', update);
  form.addEventListener('input', invalidate);
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const token = ++revision;
    const query = new URLSearchParams({element: element.value, engine: engine.value, family: family.value,
      xc: xc.value, relativity: relativity.value, profile: profile.value, format: 'upf'});
    for (const [key, input] of inputByKey) {
      if (input.type === 'checkbox') { if (input.checked) query.set(key, '1'); }
      else if (input.value.trim()) query.set(key, input.value.trim());
    }
    result.replaceChildren(make('p', 'Checking physics choices…', 'loading'));
    const response = await API.buildCommand(query);
    if (token !== revision) return;
    result.replaceChildren();
    if (response.status !== 200 || !response.body.command) {
      result.append(make('p', response.body.reason || response.body.message || 'The command could not be built. Try again.', 'error'));
      return;
    }
    const pre = make('pre', response.body.command); pre.id = 'custom-command'; result.append(pre);
    const copy = make('button', 'Copy command', 'btn'); copy.type = 'button';
    copy.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(pre.textContent); copy.textContent = 'Copied'; }
      catch (_) { copy.textContent = 'Select and copy the command above'; }
    });
    result.append(copy, make('p', 'Run with --dry-run first to inspect the exact native input before generation.', 'hint'));
  });
  update();
});
