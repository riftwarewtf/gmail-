/* Covers provider failover and the unreachable-provider diagnostic. */
const { chromium } = require('playwright');
const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8123';
const DOMAINS = { 'hydra:member': [{ domain: 'example.test', isActive: true }] };

(async () => {
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}
  );
  const results = [];
  const check = (n, ok, extra='') => results.push(`${ok?'PASS':'FAIL'}  ${n}${extra?' — '+extra:''}`);

  // --- case 1: mail.tm unreachable, mail.gw fine -> silent failover ---
  {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await ctx.route('**://api.mail.tm/**', r => r.abort('connectionfailed'));
    await ctx.route('**://api.mail.gw/**', r =>
      r.fulfill({ status:200, contentType:'application/json', body: JSON.stringify(DOMAINS) }));
    await page.goto(`${BASE_URL}/index.html`, { waitUntil:'networkidle' });

    await page.waitForFunction(() => document.getElementById('domain-select').value !== '', { timeout:15000 });
    check('fails over to the second provider', await page.inputValue('#provider-select') === 'mailgw');
    check('domains load after failover', (await page.locator('#domain-select option').count()) === 1);
    check('generate is enabled after failover', !(await page.locator('#create-btn').isDisabled()));
    check('failover toast shown', (await page.locator('.toast--warn').count()) >= 1);
    await ctx.close();
  }

  // --- case 2: both unreachable -> diagnostic with a probe link ---
  {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    await ctx.route('**://api.mail.tm/**', r => r.abort('connectionfailed'));
    await ctx.route('**://api.mail.gw/**', r => r.abort('connectionfailed'));
    await page.goto(`${BASE_URL}/index.html`, { waitUntil:'networkidle' });

    await page.waitForSelector('.hint--error', { timeout:15000 });
    await page.waitForSelector('.hint--error a', { timeout:15000 });
    const hint = await page.textContent('.hint--error');
    check('diagnostic names a blocker as the likely cause', /blocker/i.test(hint));
    check('diagnostic mentions the IP challenge case', /challenging your IP/i.test(hint));

    const href = await page.getAttribute('.hint--error a', 'href');
    check('probe link points at the live domains endpoint',
      href === 'https://api.mail.gw/domains?page=1', href);
    check('probe link opens in a new tab',
      (await page.getAttribute('.hint--error a', 'target')) === '_blank');
    check('generate stays disabled', await page.locator('#create-btn').isDisabled());
    check('no infinite failover loop', (await page.locator('.toast--warn').count()) === 1);
    await ctx.close();
  }

  console.log(results.join('\n'));
  const failed = results.filter(r => r.startsWith('FAIL')).length;
  console.log(`\n${results.length-failed}/${results.length} checks passed`);
  await browser.close();
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error('harness error:', e); process.exit(2); });
