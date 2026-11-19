/* ---------------------------------------------------------------------------
 * repair.js -- client logic for /repair/ page
 * Cross-engine repair, defect taxonomy inspection, dry-run preview & apply
 * ------------------------------------------------------------------------- */
'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const host = document.getElementById('repair-app');
  if (!host) return;

  const make = (tag, text, className) => {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (className) node.className = className;
    return node;
  };

  // Intro & evidence ladder overview
  const intro = make('section');
  intro.append(
    make('h2', 'Defect Taxonomy & Evidence Ladder'),
    make('p', 'PseudoForge pairs automated defect detectors with single-engine and cross-engine repair pathways. All repairs operate non-destructively in timestamped directories, preserving original outputs.')
  );

  const ladderBox = make('div', '', 'repair-card');
  ladderBox.append(
    make('h3', 'Binding Evidence Ladder (L1–L6)'),
    make('p', 'Repairs are graded on the level of physical evidence they reach, not binary success:'),
    (() => {
      const ul = make('ul');
      const items = [
        ['L1: Native Generation', 'Engine finishes without crash (all 9 engines verified).'],
        ['L2: Valid Serialization', 'UPF / XML parses cleanly under format validators.'],
        ['L3: Consumer SCF Convergence', 'Target DFT consumer reaches ground-state convergence.'],
        ['L4: Atomic Diagnostics', 'Ghost checks, logarithmic derivatives, energy conservation verified.'],
        ['L5: Material Accuracy', 'Lattice constant / bulk modulus vs all-electron reference (Si verified).'],
        ['L6: Independent Transferability', 'Verification on an uncalibrated chemical family (EMPTY).']
      ];
      for (const [title, desc] of items) {
        const li = make('li');
        const strong = make('strong', title + ': ');
        li.append(strong, document.createTextNode(desc));
        ul.append(li);
      }
      return ul;
    })(),
    make('p', 'training_core_hours is single-logical-CPU active training wall time enforced by CPU affinity. It is not a scheduler reservation; cluster-accounting adapters are future work.', 'hint')
  );
  intro.append(ladderBox);

  // Status message container
  const statusMsg = make('div', '', 'status-msg');
  statusMsg.hidden = true;
  statusMsg.setAttribute('aria-live', 'polite');

  const setStatus = (type, text) => {
    statusMsg.className = 'status-msg ' + type;
    statusMsg.textContent = text;
    statusMsg.hidden = !text;
  };

  // Section 1: Taxonomy browser
  const taxSec = make('section');
  taxSec.append(make('h2', 'Defect Taxonomy Registry'));
  const taxContainer = make('div', '', 'repair-grid');
  taxSec.append(taxContainer);

  const loadTaxonomy = async () => {
    setStatus('loading', 'Loading defect taxonomy…');
    try {
      const res = await API.defects();
      if (res.status !== 200 || !Array.isArray(res.body)) {
        throw new Error((res.body && res.body.message) || 'Failed to load taxonomy.');
      }
      setStatus('', '');
      taxContainer.replaceChildren();
      if (!res.body.length) {
        taxContainer.append(make('p', 'No defects registered in taxonomy.', 'status-msg empty'));
        return;
      }
      for (const d of res.body) {
        const card = make('div', '', 'repair-card');
        const header = make('h3', d.id);
        const sub = make('p', `Engine: ${d.engine} | Defect Class: ${d.class}`, 'hint');
        const details = make('p', `Detector: ${d.detector} (${d.detector_location})\nRepair: ${d.repair_strategy} (${d.repair_parameters})`);
        details.style.whiteSpace = 'pre-wrap';
        
        let evidenceLevel = 'L4';
        if (d.class.includes('accuracy') || d.evidence_source.includes('silicon')) evidenceLevel = 'L5';
        else if (d.class.includes('convergence') || d.class.includes('serialization')) evidenceLevel = 'L3';

        const badge = make('span', evidenceLevel + ' Diagnostic', 'repair-badge badge-' + evidenceLevel.toLowerCase());
        
        card.append(header, sub, badge, details);
        if (d.cross_engine_strategy && d.cross_engine_strategy !== 'none') {
          const cross = make('p', `Cross-engine strategy: ${d.cross_engine_strategy} (donor: ${d.cross_engine_source})`, 'hint');
          card.append(cross);
        }
        taxContainer.append(card);
      }
    } catch (err) {
      setStatus('error', err.message);
    }
  };

  // Section 2: Project diagnosis and repair runner
  const runnerSec = make('section');
  runnerSec.append(make('h2', 'Inspect & Repair Project'));

  const form = make('form');
  form.id = 'repair-form';

  const projField = make('div', '', 'cmp-field');
  const projLabel = make('label', 'Project Directory Path:');
  projLabel.htmlFor = 'repair-proj-input';
  const projInput = make('input');
  projInput.type = 'text';
  projInput.id = 'repair-proj-input';
  projInput.placeholder = 'e.g. examples/design-si or outputs/project-dir';
  projInput.required = true;
  projField.append(projLabel, projInput);

  const actions = make('div', '', 'repair-actions');
  const detectBtn = make('button', 'Detect Defects (Plan)', 'btn');
  detectBtn.type = 'submit';
  actions.append(detectBtn);
  form.append(projField, actions);

  const resultsArea = make('div', '', 'repair-grid');

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const proj = projInput.value.trim();
    if (!proj) return;

    setStatus('loading', `Inspecting project at ${proj}…`);
    detectBtn.disabled = true;
    resultsArea.replaceChildren();

    try {
      const res = await API.repairPlan({ project: proj });
      detectBtn.disabled = false;
      if (res.status !== 200) {
        throw new Error((res.body && res.body.message) || `Error detecting defects (HTTP ${res.status}).`);
      }
      setStatus('success', `Inspection complete. Found ${res.body.detected_count || 0} defect(s).`);

      if (!res.body.defects || !res.body.defects.length) {
        resultsArea.append(make('p', 'No defects detected in this project. All verified detectors report clean output.', 'status-msg empty'));
        return;
      }

      for (const d of res.body.defects) {
        const card = make('div', '', 'repair-card');
        card.append(
          make('h3', `Defect: ${d.id}`),
          make('p', `Class: ${d.class} | Engine: ${d.engine}`, 'hint'),
          make('p', `Detector: ${d.detector} (${d.detector_location})`)
        );

        // Single-engine strategy preview
        const singleBox = make('div', '', 'repair-preview-box');
        singleBox.append(
          make('strong', 'Single-Engine Repair: '),
          document.createTextNode(`${d.single_engine.strategy} [${d.single_engine.parameters}]`)
        );
        card.append(singleBox);

        const cardActions = make('div', '', 'repair-actions');
        const applySingleBtn = make('button', 'Apply Single Repair', 'btn');
        applySingleBtn.type = 'button';
        applySingleBtn.addEventListener('click', async () => {
          await runApply(proj, d.id, d.single_engine.strategy, null, card);
        });
        cardActions.append(applySingleBtn);

        // Cross-engine strategy preview if available
        if (d.cross_engine && d.cross_engine.strategy && d.cross_engine.strategy !== 'none') {
          const crossBox = make('div', '', 'repair-preview-box');
          crossBox.append(
            make('strong', 'Cross-Engine Repair: '),
            document.createTextNode(`${d.cross_engine.strategy} [donor: ${d.cross_engine.donor_engine}]`)
          );
          card.append(crossBox);

          const applyCrossBtn = make('button', 'Apply Cross Repair', 'btn');
          applyCrossBtn.type = 'button';
          applyCrossBtn.addEventListener('click', async () => {
            await runApply(proj, d.id, 'cross_engine_repair', d.cross_engine.donor_engine, card);
          });
          cardActions.append(applyCrossBtn);
        }

        card.append(cardActions);
        resultsArea.append(card);
      }
    } catch (err) {
      detectBtn.disabled = false;
      setStatus('error', err.message);
    }
  });

  const runApply = async (project, defectId, strategy, donorEngine, parentCard) => {
    setStatus('loading', `Applying ${strategy} for ${defectId}…`);
    try {
      const res = await API.repairApply({
        project,
        defect_id: defectId,
        strategy,
        donor_engine: donorEngine
      });
      if (res.status !== 200) {
        throw new Error((res.body && res.body.message) || `Failed to apply repair (HTTP ${res.status}).`);
      }
      setStatus('success', `Repair applied successfully for ${defectId}!`);
      
      const repBox = make('div', '', 'repair-preview-box');
      const outcome = res.body.outcome || res.body.status || 'improved';
      const evidenceLevel = (strategy === 'cross_engine_repair') ? 'L4/L5' : 'L4';
      repBox.append(
        make('strong', `Repair Result: ${outcome.toUpperCase()} (Evidence Level: ${evidenceLevel})\n`),
        document.createTextNode(JSON.stringify(res.body, null, 2))
      );
      parentCard.append(repBox);
    } catch (err) {
      setStatus('error', err.message);
    }
  };

  runnerSec.append(form, resultsArea);
  host.append(intro, statusMsg, taxSec, runnerSec);

  loadTaxonomy();
});
