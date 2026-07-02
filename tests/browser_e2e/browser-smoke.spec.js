const { test, expect, chromium, firefox } = require('@playwright/test');

const defaultHeadless = process.env.RPA_BROWSER_HEADLESS !== '0';

async function runBasicInputFlow(browserType, launchOptions = {}) {
  const browser = await browserType.launch({ headless: defaultHeadless, ...launchOptions });
  try {
    const page = await browser.newPage();
    await page.setContent(`
      <html>
        <body>
          <label for="q">Query</label>
          <input id="q" />
          <button id="submit">Submit</button>
          <div id="result"></div>
          <script>
            document.querySelector('#submit').addEventListener('click', () => {
              document.querySelector('#result').textContent =
                document.querySelector('#q').value;
            });
          </script>
        </body>
      </html>
    `);
    await page.locator('#q').fill('rpad browser lab');
    await page.locator('#submit').click({ force: true });
    await expect(page.locator('#result')).toHaveText('rpad browser lab');
  } finally {
    await browser.close();
  }
}

test('chromium can click and type', async () => {
  await runBasicInputFlow(chromium);
});

test('firefox can click and type', async () => {
  const firefoxPath = process.env.FIREFOX_PATH;
  await runBasicInputFlow(firefox, firefoxPath ? { executablePath: firefoxPath } : {});
});

test('360 browser can click and type when provided', async () => {
  const qihu360Path = process.env.QIHU360_PATH;
  test.skip(!qihu360Path, 'Set QIHU360_PATH to 360se.exe.');
  test.skip(process.env.RPA_PLAYWRIGHT_360 !== '1', '360 desktop coverage runs through the native VM smoke by default.');

  await runBasicInputFlow(chromium, { executablePath: qihu360Path, headless: false });
});
