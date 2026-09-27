/*
 * End-to-end smoke test against a mocked mail.tm provider.
 *
 *   npx http-server -p 8123 . &
 *   node tests/e2e.js
 *
 * Override the target with BASE_URL, and the browser with CHROMIUM_PATH.
 */
const { chromium } = require('playwright');

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8123';

const DOMAINS = {
  'hydra:member': [
    { domain: 'example.test', isActive: true, isPrivate: false },
    { domain: 'second.test', isActive: true, isPrivate: false },
  ],
};

const MESSAGE_SUMMARY = {
  id: 'msg-1',
  from: { name: 'Acme Signup', address: 'noreply@acme.test' },
  subject: 'Confirm your address',
  intro: 'Click the link to confirm…',
  seen: false,
  hasAttachments: true,
  createdAt: new Date().toISOString(),
};

const MESSAGE_FULL = {
  ...MESSAGE_SUMMARY,
  html: [
    '<p>Hello there <b>friend</b></p>' +
    '<script>window.__PWNED = true;<\/script>' +
    '<img src="https://tracker.test/pixel.gif" alt="pixel">' +
    '<a href="https://acme.test/confirm" onclick="window.__PWNED=true">Confirm</a>' +
    '<iframe src="https://evil.test"></iframe>',
  ],
  text: 'Hello there friend',
  attachments: [
    { id: 'att-1', filename: 'invoice.pdf', size: 20480, downloadUrl: '/messages/msg-1/attachment/att-1' },
  ],
};

let deliverMail = false;
const errors = [];
const requests = [];

(async () => {
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}
  );
  const ctx = await browser.newContext();
  const page = await ctx.newPage();

  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(`console: ${m.text()}`);
  });

  // Keep the other backends deterministic: this suite exercises mail.tm only.
  for (const host of ['api.mail.gw', 'api.maildrop.cc', 'dropmail.me']) {
    await ctx.route(`**://${host}/**`, (r) => r.abort('connectionfailed'));
  }

  await ctx.route('**://api.mail.tm/**', async (route) => {
    const url = new URL(route.request().url());
    const method = route.request().method();
    requests.push(`${method} ${url.pathname}`);
    const json = (body, status = 200) =>
      route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

    if (url.pathname === '/domains') return json(DOMAINS);
    if (url.pathname === '/accounts' && method === 'POST') {
      const body = JSON.parse(route.request().postData() || '{}');
      return json({ id: 'acc-1', address: body.address }, 201);
    }
    if (url.pathname === '/token') return json({ token: 'tok-abc', id: 'acc-1' });
    if (url.pathname === '/messages') return json({ 'hydra:member': deliverMail ? [MESSAGE_SUMMARY] : [] });
    if (url.pathname === '/messages/msg-1' && method === 'GET') return json(MESSAGE_FULL);
    if (url.pathname === '/messages/msg-1' && method === 'PATCH') return json({ ...MESSAGE_FULL, seen: true });
    if (url.pathname.includes('/attachment/')) {
      return route.fulfill({ status: 200, contentType: 'application/pdf', body: 'fake-pdf' });
    }
    return json({ 'hydra:description': 'unmocked' }, 404);
  });

  const results = [];
  const check = (name, ok, extra = '') =>
    results.push(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? ' — ' + extra : ''}`);

  await page.goto(`${BASE_URL}/index.html`, { waitUntil: 'networkidle' });

  // --- domains load ---
  await page.waitForFunction(
    () => document.getElementById('domain-select').options.length > 0 &&
          document.getElementById('domain-select').value !== '',
    { timeout: 10000 }
  );
  const domainCount = await page.locator('#domain-select option').count();
  check('domains populate the dropdown', domainCount === 2, `${domainCount} options`);
  check('auto mode is selected by default', (await page.inputValue('#provider-select')) === 'auto');
  const autoLabel = await page.locator('#provider-select option[value="auto"]').textContent();
  check('auto-probe resolved to the reachable backend', /mail\.tm/.test(autoLabel), autoLabel);
  const gwLabel = await page.locator('#provider-select option[value="mailgw"]').textContent();
  check('unreachable backends are marked in the picker', /no answer/.test(gwLabel), gwLabel);

  check('reader pane takes no space before a message is opened',
    (await page.locator('#reader').boundingBox()) === null);
  check('address bar hidden with no mailbox', await page.locator('#address-bar').isHidden());

  const prefilled = await page.inputValue('#username-input');
  check('username is pre-generated', prefilled.length > 3, prefilled);

  // --- create a mailbox ---
  await page.click('#create-btn');
  await page.waitForSelector('#address-bar:not([hidden])', { timeout: 10000 });
  const address = (await page.textContent('#active-address')).trim();
  check('mailbox address shown', /@example\.test$/.test(address), address);
  check('mailbox listed in sidebar', (await page.locator('.account').count()) === 1);
  check('creation toast appeared', (await page.locator('.toast').count()) >= 1);

  // --- persistence across reload ---
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('#address-bar:not([hidden])', { timeout: 10000 });
  check('mailbox survives a reload', (await page.textContent('#active-address')).trim() === address);

  // --- mail arrives ---
  deliverMail = true;
  await page.click('#refresh-btn');
  await page.waitForSelector('.message', { timeout: 10000 });
  check('message appears in the list', (await page.locator('.message').count()) === 1);
  check('placeholder overlay hidden once mail arrives', await page.locator('#inbox-placeholder').isHidden());
  check('message is marked unread', await page.locator('.message').first().evaluate((n) => n.classList.contains('is-unread')));
  check('unread badge on the mailbox', (await page.textContent('.account__badge')).trim() === '1');
  check('favicon badge painted', await page.evaluate(() => {
    const l = document.querySelector('link[rel~="icon"]');
    return !!l && l.href.startsWith('data:image/png');
  }));
  check('title carries unread count', (await page.title()).startsWith('(1)'));
  check('new-mail toast fired', (await page.locator('.toast--mail').count()) >= 1);

  // --- open it ---
  await page.click('.message');
  await page.waitForSelector('#reader:not([hidden])', { timeout: 10000 });
  check('subject rendered', (await page.textContent('#reader-subject')).includes('Confirm your address'));
  check('sender rendered', (await page.textContent('#reader-from')).includes('noreply@acme.test'));
  check('attachment listed', (await page.locator('.attachment').count()) === 1);

  const frame = page.frameLocator('#reader-frame');
  await frame.locator('body').waitFor({ timeout: 10000 });
  const frameHtml = await frame.locator('body').innerHTML();

  check('body text rendered', frameHtml.includes('Hello there'));
  check('script tag stripped', !/<script/i.test(frameHtml));
  check('iframe stripped', !/<iframe/i.test(frameHtml));
  check('inline handler stripped', !/onclick/i.test(frameHtml));
  check('no script executed', (await page.evaluate(() => window.__PWNED)) === undefined);
  check('remote image blocked', /data-blocked/.test(frameHtml) && !/tracker\.test/.test(frameHtml));
  check('link hardened', /rel="noopener noreferrer nofollow"/.test(frameHtml));
  check('"Load images" offered', await page.locator('#reader-images').isVisible());

  // --- unblock images ---
  await page.click('#reader-images');
  await page.waitForTimeout(400);
  const unblocked = await page.frameLocator('#reader-frame').locator('body').innerHTML();
  check('images load on request', /tracker\.test/.test(unblocked));

  // --- read state ---
  await page.waitForTimeout(600);
  check('message marked read', !(await page.locator('.message').first().evaluate((n) => n.classList.contains('is-unread'))));
  check('title badge cleared', !(await page.title()).startsWith('('));

  // --- iframe is sized to its content ---
  const h = await page.locator('#reader-frame').evaluate((n) => parseInt(n.style.height || '0', 10));
  check('reader frame auto-sized', h > 24, `${h}px`);

  // --- theme toggle (initial value follows the OS preference, so assert relatively) ---
  const themeBefore = await page.getAttribute('html', 'data-theme');
  await page.click('#toggle-theme');
  const themeAfter = await page.getAttribute('html', 'data-theme');
  check('theme toggles', themeAfter !== themeBefore, `${themeBefore} -> ${themeAfter}`);
  await page.click('#toggle-theme');
  check('theme toggles back', (await page.getAttribute('html', 'data-theme')) === themeBefore);

  // --- close reader, delete mailbox ---
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  check('Escape closes the reader', await page.locator('#reader').isHidden());

  page.on('dialog', (d) => d.accept());
  await page.click('#delete-account-btn');
  await page.waitForTimeout(900);
  check('mailbox removed', (await page.locator('.account').count()) === 0);

  // --- mobile layout ---
  await page.setViewportSize({ width: 390, height: 780 });
  await page.waitForTimeout(300);
  check('back button shows on narrow screens', await page.locator('#back-btn').isVisible() || (await page.locator('#address-bar').isHidden()));
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check('no horizontal overflow on mobile', overflow <= 1, `${overflow}px`);

  // The header has to fit a wordmark, the provider picker and three buttons.
  const collide = await page.evaluate(() => {
    const boxes = [...document.querySelectorAll('.brand, #provider-select, .icon-btn')]
      .map((n) => n.getBoundingClientRect())
      .filter((r) => r.width > 0);
    for (let i = 0; i < boxes.length; i += 1) {
      for (let j = i + 1; j < boxes.length; j += 1) {
        const a = boxes[i]; const b = boxes[j];
        if (a.left < b.right - 1 && b.left < a.right - 1 &&
            a.top < b.bottom - 1 && b.top < a.bottom - 1) return `${i}x${j}`;
      }
    }
    return null;
  });
  check('header elements do not overlap on mobile', collide === null, collide || 'clear');

  console.log(results.join('\n'));
  console.log('\nrequests: ' + [...new Set(requests)].join(', '));
  console.log('\njs errors: ' + (errors.length ? '\n  ' + errors.join('\n  ') : 'none'));
  const failed = results.filter((r) => r.startsWith('FAIL')).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);

  await browser.close();
  process.exit(failed || errors.length ? 1 : 0);
})().catch((e) => {
  console.error('harness error:', e);
  process.exit(2);
});
