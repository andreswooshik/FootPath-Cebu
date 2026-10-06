/* Optional integration test driven by Django's isolated StaticLiveServerTestCase.
   Set FOOTPATH_PLAYWRIGHT_MODULE to a locally installed playwright module. */
const assert = require('node:assert/strict');
const { chromium } = require(process.env.FOOTPATH_PLAYWRIGHT_MODULE);
const urls = JSON.parse(process.env.FOOTPATH_REVIEW_URLS);

(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.FOOTPATH_BROWSER_EXECUTABLE
      ? { executablePath: process.env.FOOTPATH_BROWSER_EXECUTABLE } : {})
  });
  const context = await browser.newContext();
  await context.addCookies([{
    name: process.env.FOOTPATH_SESSION_COOKIE_NAME,
    value: process.env.FOOTPATH_SESSION_COOKIE,
    url: new URL('/', urls.approve).href
  }]);
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  let posts = 0;
  page.on('request', (request) => { if (request.method() === 'POST') posts++; });
  const dialog = page.locator('[data-review-dialog]');
  const confirm = page.locator('[data-review-confirm]');
  const cancel = page.locator('[data-review-cancel]');
  const status = page.locator('.fp-application-review__status');

  async function open(scenario, approving) {
    const response = await page.goto(urls[scenario]);
    assert.equal(response.status(), 200, 'Review page should load: ' + scenario);
    assert.equal(page.url(), urls[scenario], 'Review page should keep its authenticated session: ' + scenario);
    const marker = page.locator('#club-registration-state');
    assert.equal(await marker.getAttribute('data-state'), 'PENDING',
      'Review page should be pending: ' + scenario + '\n' + await page.locator('body').innerText());
    const count = posts;
    await page.locator(approving ? '[name="_approve_application"]' : '[name="_not_approve_application"]').click();
    await dialog.waitFor({ state: 'visible' });
    assert.equal(posts, count, 'Opening confirmation must make no POST');
    assert.match(await dialog.innerText(), new RegExp(scenario + ' "FC" <Cebu>'));
    assert.equal(await confirm.innerText(), approving ? 'Approve' : 'Reject');
    assert.equal(await status.textContent(), 'Pending review');
  }

  async function settled() {
    await dialog.waitFor({ state: 'hidden' });
    assert.equal(await page.locator('#club_form').getAttribute('aria-busy'), 'false');
  }

  try {
    // Cancel both decisions and Escape without navigating away or submitting.
    await open('approve', true);
    let count = posts;
    await cancel.click();
    assert.equal(posts, count);
    await page.locator('[name="_not_approve_application"]').click();
    await cancel.click();
    assert.equal(posts, count);
    await page.locator('[name="_approve_application"]').click();
    await page.keyboard.press('Escape');
    assert.equal(posts, count);
    assert.equal(page.url(), urls.approve);

    // Hold the actual POST to check loading, Cancel/Escape, and rapid resubmissions.
    await page.locator('[name="_approve_application"]').click();
    let release;
    const held = new Promise((resolve) => { release = resolve; });
    await page.route(urls.approve, async (route) => {
      if (route.request().method() === 'POST') await held;
      await route.continue();
    });
    await confirm.click();
    assert.equal(await confirm.isDisabled(), true);
    assert.equal(await cancel.isDisabled(), true);
    assert.equal(await confirm.innerText(), 'Approving...');
    await page.keyboard.press('Escape');
    assert.equal(await dialog.isVisible(), true);
    await confirm.evaluate((button) => { button.click(); button.click(); button.click(); });
    release();
    await settled();
    assert.equal(posts, count + 1, 'Repeated clicks must execute one POST');
    assert.equal(await status.textContent(), 'Approved');
    assert.match(await page.locator('#club-review-messages').innerText(), /approved successfully/);
    assert.equal(page.url(), urls.approve, 'Fetch must preserve the details page');
    await page.unroute(urls.approve);

    await open('reject', false);
    count = posts;
    await confirm.evaluate((button) => { button.click(); button.click(); });
    await settled();
    assert.equal(posts, count + 1);
    assert.equal(await status.textContent(), 'Not approved');
    assert.match(await page.locator('#club-review-messages').innerText(), /rejected successfully/);

    for (const [scenario, approving] of [['approve-failure', true], ['reject-failure', false]]) {
      await open(scenario, approving);
      await confirm.click();
      await settled();
      assert.equal(await status.textContent(), 'Pending review');
      assert.equal(await page.locator('[name="_approve_application"]').isEnabled(), true);
      const message = await page.locator('#club-review-messages').innerText();
      assert.match(message, /failed/);
      assert.doesNotMatch(message, /successfully/);
    }

    await open('network-failure', true);
    await page.route(urls['network-failure'], (route) => route.request().method() === 'POST'
      ? route.abort() : route.continue());
    await confirm.click();
    await settled();
    assert.equal(await status.textContent(), 'Pending review');
    assert.match(await page.locator('#club-review-messages').innerText(), /Current application status: Pending/);
    await page.unroute(urls['network-failure']);
    await page.locator('[name="_approve_application"]').click();
    await confirm.click();
    await settled();
    assert.equal(await status.textContent(), 'Approved');

    await open('lost-response', true);
    await page.route(urls['lost-response'], async (route) => {
      if (route.request().method() === 'POST') {
        await route.fetch(); // Commit the decision, then lose its response.
        await route.abort();
      } else await route.continue();
    });
    await confirm.click();
    await settled();
    assert.equal(await status.textContent(), 'Approved');
    assert.equal(await page.locator('.fp-application-review__actions').isVisible(), false);
    assert.match(await page.locator('#club-review-messages').innerText(), /Current application status: Approved/);
    await page.unroute(urls['lost-response']);

    // A decision by another administrator must block the stale dialog.
    await open('stale', false);
    const csrf = await page.locator('[name="csrfmiddlewaretoken"]').first().inputValue();
    const reviewed = await page.request.post(urls.stale, { form: {
      csrfmiddlewaretoken: csrf, _approve_application: '1', _confirm_application: '1'
    } });
    assert.equal(reviewed.ok(), true);
    await confirm.click();
    await settled();
    assert.equal(await status.textContent(), 'Approved');
    assert.match(await page.locator('#club-review-messages').innerText(), /already been reviewed/);

    const listURL = new URL('../..', urls.approve);
    listURL.searchParams.set('registration_state', 'PENDING');
    await page.goto(listURL.href);
    const list = await page.locator('#result_list').innerText();
    assert.doesNotMatch(list, /approve "FC"|reject "FC"/);
    assert.match(list, /approve-failure "FC"/);

    const noJS = await browser.newContext({ javaScriptEnabled: false });
    await noJS.addCookies(await context.cookies());
    const fallback = await noJS.newPage();
    await fallback.goto(urls['no-javascript']);
    await fallback.locator('[name="_approve_application"]').click();
    assert.match(await fallback.locator('[data-review-fallback]').innerText(), /Approve Club Application\?/);
    await fallback.getByRole('link', { name: 'Cancel', exact: true }).click();
    assert.equal(await fallback.locator('.fp-application-review__status').textContent(), 'Pending review');
    await fallback.locator('[name="_approve_application"]').click();
    await fallback.locator('[data-review-fallback] button').click();
    assert.equal(await fallback.locator('#club-registration-state').getAttribute('data-state'), 'APPROVED');
    await noJS.close();

    assert.deepEqual(errors, [], 'No JavaScript errors should occur');
    console.log('PASS: cancel, confirm, double clicks, loading, failures, lost responses, stale decisions, list refresh, and no-JavaScript confirmation');
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
