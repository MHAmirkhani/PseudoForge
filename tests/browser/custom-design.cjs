// Optional live test: install Playwright and @axe-core/playwright externally.
// PF_WEB_BASE_URL points at serve-local.sh; PF_CHROME_BIN is optional.
const assert = require('node:assert/strict');
const {chromium} = require('playwright');
const {AxeBuilder} = require('@axe-core/playwright');

(async () => {
  const browser = await chromium.launch({headless: true, ...(process.env.PF_CHROME_BIN ? {executablePath: process.env.PF_CHROME_BIN} : {})});
  try {
    const base = process.env.PF_WEB_BASE_URL || 'http://127.0.0.1:8080';
    const context = await browser.newContext({viewport: {width: 1280, height: 900}});
    const page = await context.newPage();
    page.setDefaultTimeout(45000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(base + '/customize/');
    await page.locator('#custom-engine').waitFor();
    await page.selectOption('#custom-engine', 'oncvpsp');
    assert.equal(await page.locator('#custom-profile').inputValue(), 'sg15');
    assert.equal(await page.locator('#control-core_hole').count(), 0);
    assert.equal(await page.locator('#control-extra_projectors').count(), 0);
    await page.fill('#control-channel_radii', 's:1.9 p:2.0');
    await page.selectOption('#control-nlcc', 'off');
    await page.fill('#control-lloc', '4');
    await page.fill('#control-rcloc', '1.8');
    await page.fill('#native-qcut-s', '5.12');
    await page.getByRole('button', {name: 'Build command', exact: true}).click();
    await page.locator('#custom-command').waitFor();
    const command = await page.locator('#custom-command').innerText();
    assert.match(command, /--channel-rc s:1.9/);
    assert.match(command, /--channel-rc p:2.0/);
    assert.match(command, /--nlcc off/);
    assert.match(command, /--engine oncvpsp/);
    assert.match(command, /(?:--profile|-p) sg15/);
    assert.match(command, /--engine-option qcut.s=5.12/);
    await page.locator('#custom-manual-command').waitFor();
    const manual = await page.locator('#custom-manual-command').innerText();
    assert.match(manual, /^pseudoforge prepare/);
    const importCommand = manual.split('# Edit files')[1];
    assert.match(importCommand, /--params .\/native-inputs\/inputs/);
    assert.doesNotMatch(importCommand, /--channel-rc|--rcut-scale|--engine-option/);
    await page.selectOption('#custom-engine', 'gth');
    assert.equal(await page.locator('#custom-format').inputValue(), 'gth');
    assert.equal(await page.locator('#custom-refit').isVisible(), true);
    await page.fill('#native-fit-eigenvalue_weight', '1.1');
    await page.getByRole('button', {name: 'Build command', exact: true}).click();
    await page.locator('#custom-manual-command').waitFor();
    assert.match(await page.locator('#custom-command').innerText(), /--refit/);
    await page.selectOption('#custom-engine', 'fhi98pp');
    assert.equal(await page.locator('#custom-xc').inputValue(), 'pw');
    assert.equal(await page.locator('#custom-format').inputValue(), 'cpi');
    assert.equal(await page.locator('#custom-refit').isVisible(), false);
    await page.selectOption('#custom-engine', 'adpack');
    assert.equal(await page.locator('#custom-rel').inputValue(), 'full');
    assert.equal(await page.locator('#custom-format').inputValue(), 'openmx');
    await page.selectOption('#custom-engine', 'atompaw');
    await page.selectOption('#custom-xc', 'r2scan');
    assert.equal(await page.locator('#custom-rel').inputValue(), 'nonrel');
    assert.notEqual(await page.locator('#custom-format').inputValue(), 'upf');
    await page.selectOption('#custom-engine', 'ld1');
    assert.equal(await page.locator('#custom-command').count(), 0);
    assert.equal(await page.locator('#control-core_hole').count(), 1);
    await page.selectOption('#custom-family', 'paw');
    assert.equal(await page.locator('#control-which_augfun').count(), 1);
    const violations = await new AxeBuilder({page}).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    assert.deepEqual(violations.violations.map(v => v.id), [], 'custom form accessibility');

    await page.goto(base + '/design/');
    await page.locator('#design-protocol').waitFor();
    await page.fill('#design-protocol', '{');
    assert.equal(await page.getByRole('button', {name: 'Download protocol'}).isDisabled(), true);
    await page.fill('#design-protocol', JSON.stringify({schema_version: 1, candidates: [{id: 'example'}], benchmarks: [{split: 'train'}, {split: 'test'}]}));
    assert.equal(await page.getByRole('button', {name: 'Download protocol'}).isEnabled(), true);
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', {name: 'Download protocol'}).click();
    assert.equal((await downloadPromise).suggestedFilename(), 'protocol.json');
    const report = {schema_version: 1, selected: 'fixture', meets_reference_constraints: false,
      reference_kinds: ['synthetic-test'], pareto: [], test: {passes: false, convergence: {passes: false}},
      results: [{id: '<img src=x onerror=alert(1)>', status: 'evaluated', training: {cost_seconds: 1, worst_normalized_error: 0.2, convergence: {passes: true}}}]};
    await page.locator('#design-report-file').setInputFiles({name: 'report.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(report))});
    await page.getByText('Synthetic test data: these results are not a physical verification.', {exact: true}).waitFor();
    assert.equal(await page.locator('#design-results img').count(), 0);
    assert.match(await page.locator('#design-results').innerText(), /<img src=x/);
    assert.equal(await page.getByRole('columnheader', {name: 'Numerical stability'}).count(), 1);
    assert.equal(await page.getByText('Held-out numerical stability failed.', {exact: true}).count(), 1);
    const designViolations = await new AxeBuilder({page}).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze();
    assert.deepEqual(designViolations.violations.map(v => v.id), [], 'design page accessibility');
    for (const route of ['/customize/', '/design/']) {
      await page.setViewportSize({width: 390, height: 844});
      await page.goto(base + route);
      await page.locator(route === '/customize/' ? '#custom-engine' : '#design-protocol').waitFor();
      const widths = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]);
      assert.ok(widths[0] <= widths[1], `horizontal overflow on ${route}: ${widths}`);
    }
    assert.deepEqual(errors, []);
    console.log('PASS: native controls, command effects, engine changes, protocol export, synthetic report scope, safe report rendering, mobile layout and WCAG checks.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
