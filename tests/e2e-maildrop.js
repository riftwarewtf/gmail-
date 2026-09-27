/*
 * maildrop path: schema-shape fallback and graceful body failure.
 *
 *   npx http-server -p 8123 . &
 *   node tests/e2e-maildrop.js
 */
const { chromium } = require('playwright');

const BASE_URL = process.env.BASE_URL || 'http://127.0.0.1:8123';
const DEAD = ['api.mail.tm', 'api.mail.gw', 'dropmail.me'];

const HEADER = {
  id: 'm-1',
  headerfrom: 'NEVERLOSE <no-reply@neverlose.test>',
  subject: 'bae',
  date: new Date(Date.now() - 60000).toISOString(),
};

(async () => {
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}
  );
  const results = [];
  const check = (n, ok, extra = '') =>
    results.push(`${ok ? 'PASS' : 'FAIL'}  ${n}${extra ? ' — ' + extra : ''}`);

  /**
   * @param acceptMessage which `message{...}` selection the fake server accepts;
   *        null rejects every one of them.
   */
  async function run(acceptMessage, introspects = false) {
    const ctx = await browser.newContext();
    const seen = [];
    for (const host of DEAD) await ctx.route(`**://${host}/**`, (r) => r.abort('connectionfailed'));

    await ctx.route('**://api.maildrop.cc/**', (route) => {
      const query = JSON.parse(route.request().postData() || '{}').query || '';
      const json = (body, status = 200) =>
        route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });

      if (/inbox\(/.test(query)) {
        return json({ data: { inbox: /mailbox:"ping"/.test(query) ? [] : [HEADER] } });
      }

      if (/__type|__schema/.test(query)) {
        seen.push(query);
        if (introspects) {
          if (/__schema/.test(query)) {
            return json({ data: { __schema: { queryType: { fields:
              [{ name: 'inbox' }, { name: 'message' }, { name: 'ping' }] } } } });
          }
          // The real shape, which none of the hardcoded guesses match.
          return json({ data: { __type: { fields:
            [{ name: 'id' }, { name: 'headerfrom' }, { name: 'text' }] } } });
        }
        return json({ errors: [{ message: 'introspection is disabled' }] }, 400);
      }

      if (/message\(/.test(query)) {
        seen.push(query);
        if (acceptMessage && query.includes(acceptMessage)) {
          return json({ data: { message: { id: 'm-1', headerfrom: HEADER.headerfrom,
            date: HEADER.date, body: 'hello from the body', text: 'hello from the body',
            html: '<p>hello from the body</p>' } } });
        }
        // How a GraphQL server actually rejects an unknown field.
        return json({ errors: [{ message: `Cannot query field "nope" on type "Message".` }] }, 400);
      }
      return json({ data: {} }, 200);
    });

    const page = await ctx.newPage();
    await page.goto(`${BASE_URL}/index.html`, { waitUntil: 'networkidle' });
    await page.waitForFunction(() => document.getElementById('domain-select').value !== '', { timeout: 20000 });
    await page.click('#create-btn');
    await page.waitForSelector('.message', { timeout: 20000 });
    await page.click('.message');
    await page.waitForSelector('#reader:not([hidden])', { timeout: 20000 });
    await page.waitForTimeout(900);
    return { ctx, page, seen };
  }

  // --- the first selection is rejected; a later one is accepted ---
  {
    const { ctx, page, seen } = await run('headerfrom date body html');
    check('retries past a rejected selection', seen.length > 1, `${seen.length} attempts`);
    check('body renders from the accepted selection',
      /hello from the body/.test(await page.frameLocator('#reader-frame').locator('body').innerHTML()));
    check('subject filled in from the listing',
      (await page.textContent('#reader-subject')).trim() === 'bae');
    check('sender filled in from the listing',
      /neverlose\.test/.test(await page.textContent('#reader-from')));
    await ctx.close();
  }

  // --- every selection rejected: header survives, real reason surfaced ---
  {
    const { ctx, page, seen } = await run(null);
    check('exhausts every fallback selection', seen.length >= 4, `${seen.length} attempts`);
    check('header still shows the subject',
      (await page.textContent('#reader-subject')).trim() === 'bae');
    check('does not collapse to "Could not open message"',
      !/Could not open/.test(await page.textContent('#reader-subject')));

    const frame = await page.frameLocator('#reader-frame').locator('body').innerHTML();
    check('explains that only the body failed', /body could not be loaded/i.test(frame));
    check('surfaces the server\'s actual GraphQL error, not just "400"',
      /Cannot query field/.test(frame), frame.slice(0, 120));
    await ctx.close();
  }

  // --- no hardcoded shape matches, but introspection reveals the real one ---
  {
    const { ctx, page, seen } = await run('id headerfrom text', true);
    check('introspects after the guesses fail',
      seen.some((q) => /__type/.test(q)), `${seen.length} attempts`);
    check('body renders from the introspected shape',
      /hello from the body/.test(await page.frameLocator('#reader-frame').locator('body').innerHTML()));
    await ctx.close();
  }

  // --- nothing works and introspection is off: report what the server offers ---
  {
    const { ctx, page } = await run(null, false);
    const frame = await page.frameLocator('#reader-frame').locator('body').innerHTML();
    check('names the rejection plainly', /rejected every query shape/i.test(frame), frame.slice(0, 90));
    await ctx.close();
  }

  console.log(results.join('\n'));
  const failed = results.filter((r) => r.startsWith('FAIL')).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  await browser.close();
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('harness error:', e); process.exit(2); });
