/*
 * Provider failover and the all-unreachable diagnostic.
 *
 *   npx http-server -p 8123 . &
 *   node tests/e2e-offline.js
 */
const { chromium } = require('playwright');

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8123';
const HOSTS = ['api.mail.tm', 'api.mail.gw', 'api.maildrop.cc', 'dropmail.me'];
const DOMAINS = { 'hydra:member': [{ domain: 'example.test', isActive: true }] };

(async () => {
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}
  );
  const results = [];
  const check = (n, ok, extra = '') =>
    results.push(`${ok ? 'PASS' : 'FAIL'}  ${n}${extra ? ' — ' + extra : ''}`);

  /** Route every backend; `live` names the one that should answer. */
  async function open(ctx, live) {
    for (const host of HOSTS) {
      await ctx.route(`**://${host}/**`, (r) =>
        host === live
          ? r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(DOMAINS) })
          : r.abort('connectionfailed')
      );
    }
    const page = await ctx.newPage();
    await page.goto(`${BASE_URL}/index.html`, { waitUntil: 'networkidle' });
    return page;
  }

  // --- auto mode picks whichever backend answers ---
  {
    const ctx = await browser.newContext();
    const page = await open(ctx, 'api.mail.gw');
    await page.waitForFunction(() => document.getElementById('domain-select').value !== '', { timeout: 20000 });

    const autoLabel = await page.locator('#provider-select option[value="auto"]').textContent();
    check('auto resolves past the dead first choice', /mail\.gw/.test(autoLabel), autoLabel);
    check('domains load from the survivor', (await page.locator('#domain-select option').count()) === 1);
    check('generate is enabled', !(await page.locator('#create-btn').isDisabled()));
    check('dead backends marked in the picker',
      /no answer/.test(await page.locator('#provider-select option[value="mailtm"]').textContent()));
    await ctx.close();
  }

  // --- an explicitly chosen backend that dies fails over ---
  {
    const ctx = await browser.newContext();
    await ctx.addInitScript(() => localStorage.setItem('tempbox.provider', 'mailtm'));
    const page = await open(ctx, 'api.maildrop.cc');
    await page.waitForFunction(() => document.getElementById('domain-select').value !== '', { timeout: 20000 });

    check('failover toast shown', (await page.locator('.toast--warn').count()) >= 1);
    check('switched to auto after the chosen one died',
      (await page.inputValue('#provider-select')) === 'auto');
    check('maildrop offers its domain',
      (await page.locator('#domain-select').inputValue()) === 'maildrop.cc');
    await ctx.close();
  }

  // --- a backend that assigns its own address disables the name field ---
  {
    const ctx = await browser.newContext();
    const page = await open(ctx, 'api.maildrop.cc');
    await page.waitForFunction(() => document.getElementById('domain-select').value !== '', { timeout: 20000 });
    check('custom names stay enabled for maildrop', !(await page.locator('#username-input').isDisabled()));
    check('shared-inbox caveat surfaced', /same inbox/i.test(await page.textContent('#generator-hint')));
    await ctx.close();
  }

  // --- nothing answers ---
  {
    const ctx = await browser.newContext();
    const page = await open(ctx, null);
    await page.waitForSelector('.hint--error a', { timeout: 20000 });

    const hint = await page.textContent('.hint--error');
    check('diagnostic names a single blocker as the cause', /blocker/i.test(hint));
    check('diagnostic explains the all-at-once failure', /every one at once/i.test(hint));
    check('probe link present', !!(await page.getAttribute('.hint--error a', 'href')));
    check('probe link opens in a new tab',
      (await page.getAttribute('.hint--error a', 'target')) === '_blank');
    check('generate stays disabled', await page.locator('#create-btn').isDisabled());
    await ctx.close();
  }

  console.log(results.join('\n'));
  const failed = results.filter((r) => r.startsWith('FAIL')).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  await browser.close();
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('harness error:', e); process.exit(2); });
