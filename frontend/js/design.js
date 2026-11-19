'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const host = document.getElementById('design-app');
  const make = (tag, text, className) => {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  };
  const intro = make('p', 'Design runs locally with atomic generators and Quantum ESPRESSO. Define candidates, structures, reference values and error limits. Training cases select the candidate; held-out cases check that choice.');
  const guide = make('a', 'Protocol format and worked example'); guide.href = '/docs/how-to/reference-design/';
  const custom = make('a', 'Explore engine-specific physics controls'); custom.href = '/customize/';
  const editor = make('section'); editor.append(make('h2', 'Prepare a local run'));
  const uploadLabel = make('label', 'Load a protocol JSON file');
  const upload = make('input'); upload.type = 'file'; upload.accept = '.json,application/json'; upload.id = 'design-protocol-file';
  uploadLabel.append(upload);
  const label = make('label', 'Protocol JSON'); label.htmlFor = 'design-protocol';
  const textarea = make('textarea'); textarea.id = 'design-protocol'; textarea.rows = 14; textarea.spellcheck = false;
  textarea.placeholder = 'Paste your protocol or load one from a file. Reference values must come from your cited calculations.';
  const notice = make('p', '', 'hint'); notice.setAttribute('aria-live', 'polite');
  const save = make('button', 'Download protocol', 'btn'); save.type = 'button'; save.disabled = true;
  const validate = () => {
    save.disabled = true;
    try {
      const protocol = JSON.parse(textarea.value);
      if (!protocol || protocol.schema_version !== 1 || !Array.isArray(protocol.candidates) || !Array.isArray(protocol.benchmarks)) throw new Error('Expected schema_version 1, candidates and benchmarks.');
      if (!protocol.candidates.length || !protocol.benchmarks.some(c => c.split === 'train') || !protocol.benchmarks.some(c => c.split === 'test')) throw new Error('Include candidates and separate train and test cases.');
      notice.textContent = 'JSON structure checked. Run the local --plan command for complete physics, path and reference validation.';
      save.disabled = false;
    } catch (error) { notice.textContent = textarea.value.trim() ? error.message : 'Your data stays in this browser.'; }
  };
  const read = async (file, handler) => {
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) { notice.textContent = 'Choose a JSON file smaller than 2 MB.'; return; }
    try { handler(await file.text()); }
    catch (error) { notice.textContent = error.message; }
  };
  upload.addEventListener('change', () => read(upload.files[0], text => { textarea.value = text; validate(); }));
  textarea.addEventListener('input', validate);
  save.addEventListener('click', () => {
    validate(); if (save.disabled) return;
    const url = URL.createObjectURL(new Blob([JSON.stringify(JSON.parse(textarea.value), null, 2) + '\n'], {type: 'application/json'}));
    const link = make('a'); link.href = url; link.download = 'protocol.json'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
  editor.append(uploadLabel, label, textarea, notice, save,
    make('pre', 'pseudoforge design protocol.json --plan -o design-plan\npseudoforge design protocol.json --pw /path/to/pw.x -o design-run\npseudoforge design --status -o design-run\npseudoforge design --resume -o design-run'));
  const results = make('section'); results.append(make('h2', 'Inspect a run'));
  const reportLabel = make('label', 'Load report.json');
  const reportFile = make('input'); reportFile.type = 'file'; reportFile.accept = '.json,application/json'; reportFile.id = 'design-report-file';
  reportLabel.append(reportFile);
  const view = make('div'); view.id = 'design-results'; view.setAttribute('aria-live', 'polite');
  const renderReport = text => {
    view.replaceChildren();
    const report = JSON.parse(text);
    if (!report || report.schema_version !== 1 || !Array.isArray(report.results)) throw new Error('This is not a PseudoForge design report.');
    const checkpoint = report.checkpoint;
    if (checkpoint?.version === 1) {
      const phases = {training: 'Training', heldout: 'Held-out evaluation', complete: 'Complete'};
      const phase = phases[checkpoint.phase] || 'Unknown phase';
      view.append(make('p', checkpoint.paused ? phase + ' paused. Resume from the local output directory.' : phase));
      if (typeof checkpoint.active?.id === 'string') view.append(make('p', 'Active candidate: ' + checkpoint.active.id));
    }
    view.append(make('p', 'Selected from training cases: ' + (report.selected || 'none')));
    if (report.search && typeof report.search.strategy === 'string') {
      const details = make('details');
      details.append(make('summary', 'Search allocation and budget'));
      const search = report.search;
      details.append(make('p', 'Strategy: ' + search.strategy));
      if (Number.isFinite(search.training_wall_seconds)) details.append(make('p', 'Training budget: ' + search.training_wall_seconds + ' s'));
      if (Number.isFinite(search.training_core_hours)) details.append(make('p', 'Local training budget: ' + search.training_core_hours + ' core-hours'));
      const usage = report.resource_accounting;
      const cpu = usage?.training_trial_cpu_seconds;
      if (Number.isFinite(cpu)) details.append(make('p', 'Measured training CPU time: ' + cpu.toFixed(2) + ' s'));
      const charged = usage?.training_elapsed_core_hours;
      if (Number.isFinite(charged)) details.append(make('p', 'Charged elapsed core-hours: ' + charged.toPrecision(4)));
      if (typeof search.stop_reason === 'string') details.append(make('p', search.stop_reason));
      const order = make('ol');
      for (const id of Array.isArray(search.trial_order) ? search.trial_order : []) {
        if (typeof id === 'string') order.append(make('li', id));
      }
      if (order.childElementCount) details.append(order);
      view.append(details);
    }
    const verified = report.meets_reference_constraints === true;
    view.append(make('p', verified ? 'The selected candidate meets the supplied reference constraints.' : 'The report does not establish that the selected candidate meets the reference constraints.', verified ? 'success' : 'hint'));
    view.append(make('p', report.verification_scope || 'Results apply only to the supplied structures, references and tolerances.', 'hint'));
    if (report.reference_kinds && report.reference_kinds.includes('synthetic-test')) view.append(make('p', 'Synthetic test data: these results are not a physical verification.', 'error'));
    const table = make('table');
    const head = make('thead'); const header = make('tr');
    const hasConvergence = report.results.some(result => result.training?.convergence);
    const headings = ['Candidate', 'Status', 'Training time (s)', 'Worst error / tolerance', 'Training frontier'];
    if (hasConvergence) headings.push('Numerical stability');
    for (const text of headings) header.append(make('th', text));
    head.append(header); table.append(head);
    const body = make('tbody');
    for (const result of report.results) {
      const row = make('tr');
      const training = result.training || {};
      const cost = Number.isFinite(training.cost_seconds) ? training.cost_seconds.toFixed(3) : '—';
      const error = Number.isFinite(training.worst_normalized_error) ? training.worst_normalized_error.toFixed(3) : '—';
      const values = [result.id, result.error || result.status, cost, error, (report.pareto || []).includes(result.id) ? 'yes' : ''];
      if (hasConvergence) values.push(training.convergence ? (training.convergence.passes ? 'Passed' : 'Failed') : 'Not measured');
      for (const text of values) row.append(make('td', String(text || '—')));
      body.append(row);
    }
    table.append(body); const scroll = make('div', '', 'table-scroll'); scroll.append(table); view.append(scroll);
    if (!report.results.length) view.append(make('p', 'This is a plan; no candidates have been measured.', 'hint'));
    if (report.test) {
      if (report.test.convergence) view.append(make('p', report.test.convergence.passes ? 'Held-out numerical stability passed.' : 'Held-out numerical stability failed.'));
      const details = make('details');
      details.append(make('summary', 'Held-out measurements'), make('pre', JSON.stringify(report.test, null, 2)));
      view.append(details);
    }
  };
  reportFile.addEventListener('change', () => read(reportFile.files[0], renderReport));
  results.append(reportLabel, view); host.append(intro, guide, make('p'), custom, editor, results); validate();
});
