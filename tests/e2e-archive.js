/*
 * Local retention: a message must outlive the provider dropping it.
 *
 *   npx http-server -p 8123 . &
 *   node tests/e2e-archive.js
 */
const { chromium } = require('playwright');

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8123';
const DEAD = ['api.mail.gw', 'api.maildrop.cc', 'dropmail.me'];

const MSG = {
  id: 'keep-me',
  from: { name: 'Acme', address: 'no-reply@acme.test' },
  subject: 'Your receipt',
  intro: 'Order #4411',
  seen: false,
  hasAttachments: false,
  createdAt: new Date(Date.now() - 120000).toISOString(),
};

let providerHasMail = true;

(async () => {
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}
  );
  const results = [];
  const check = (n, ok, extra = '') =>
    results.push(`${ok ? 'PASS' : 'FAIL'}  ${n}${extra ? ' — ' + extra : ''}`);

  // One context throughout: IndexedDB has to persist across reloads.
  const ctx = await browser.newContext();
  for (const host of DEAD) await ctx.route(`**://${host}/**`, (r) => r.abort('connectionfailed'));

  await ctx.route('**://api.mail.tm/**', (route) => {
    const url = new URL(route.request().url());
    const json = (b, s = 200) =>
      route.fulfill({ status: s, contentType: 'application/json', body: JSON.stringify(b) });

    if (url.pathname === '/domains') return json({ 'hydra:member': [{ domain: 'example.test', isActive: true }] });
    if (url.pathname === '/accounts') return json({ id: 'acc-1' }, 201);
    if (url.pathname === '/token') return json({ token: 't', id: 'acc-1' });
    if (url.pathname === '/messages') return json({ 'hydra:member': providerHasMail ? [MSG] : [] });
    if (url.pathname === '/messages/keep-me') {
      if (!providerHasMail) return json({ 'hydra:description': 'Not found.' }, 404);
      return json({ ...MSG, html: ['<p>Thanks for your order.</p>'], text: 'Thanks for your order.', attachments: [] });
    }
    return json({}, 404);
  });

  const page = await ctx.newPage();
  await page.goto(`${BASE_URL}/index.html`, { waitUntil: 'networkidle' });
  await page.waitForFunction(() => document.getElementById('domain-select').value !== '', { timeout: 20000 });
  await page.click('#create-btn');
  await page.waitForSelector('.message', { timeout: 20000 });

  // Open it once so the body gets archived.
  await page.click('.message');
  await page.waitForSelector('#reader:not([hidden])', { timeout: 20000 });
  await page.waitForTimeout(800);
  check('body renders while the provider still has it',
    /Thanks for your order/.test(await page.frameLocator('#reader-frame').locator('body').innerHTML()));
  await page.keyboard.press('Escape');

  check('archived row written to IndexedDB', await page.evaluate(() => new Promise((resolve) => {
    const req = indexedDB.open('tempbox-archive', 1);
    req.onsuccess = () => {
      const all = req.result.transaction('messages', 'readonly').objectStore('messages').getAll();
      all.onsuccess = () => resolve(all.result.some((r) => r.id === 'keep-me' && r.full === true));
      all.onerror = () => resolve(false);
    };
    req.onerror = () => resolve(false);
  })));

  // --- the provider now drops it entirely ---
  providerHasMail = false;
  await page.click('#refresh-btn');
  await page.waitForTimeout(1200);

  check('message survives the provider dropping it',
    (await page.locator('.message').count()) === 1);
  check('marked as served from local storage',
    (await page.locator('.message__archived').count()) === 1);
  check('subject still correct',
    /Your receipt/.test(await page.textContent('.message__subject')));

  await page.click('.message');
  await page.waitForSelector('#reader:not([hidden])', { timeout: 20000 });
  await page.waitForTimeout(800);
  const body = await page.frameLocator('#reader-frame').locator('body').innerHTML();
  check('archived body still opens', /Thanks for your order/.test(body));
  check('does not show a fetch error', !/could not be loaded/i.test(body));

  // --- and across a reload ---
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('.message', { timeout: 20000 });
  check('survives a page reload', (await page.locator('.message').count()) === 1);
  check('still flagged as local after reload', (await page.locator('.message__archived').count()) === 1);

  // --- no phantom notification for archive-only mail ---
  check('archived mail does not re-notify', (await page.locator('.toast--mail').count()) === 0);

  console.log(results.join('\n'));
  const failed = results.filter((r) => r.startsWith('FAIL')).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  await browser.close();
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('harness error:', e); process.exit(2); });
