const { test, expect, chromium } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

test('chromium can load an unpacked extension build when provided', async () => {
  const extensionPath = process.env.RPAD_EXTENSION_BUILD;
  test.skip(!extensionPath, 'Set RPAD_EXTENSION_BUILD to an unpacked extension directory.');

  const userDataDir = path.join(process.env.TEMP || 'C:\\Windows\\Temp', `rpad-ext-${Date.now()}`);
  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    args: [
      `--disable-extensions-except=${extensionPath}`,
      `--load-extension=${extensionPath}`,
      '--force-renderer-accessibility=complete'
    ]
  });

  try {
    let [background] = context.serviceWorkers();
    if (!background) {
      background = await context.waitForEvent('serviceworker', { timeout: 10000 });
    }

    await expect.poll(() => background.url()).toContain('/assets/background.js');
    const extensionId = background.url().split('/')[2];
    expect(extensionId).toBeTruthy();

    const manifest = JSON.parse(fs.readFileSync(path.join(extensionPath, 'manifest.json'), 'utf8'));
    const optionsPage = manifest.options_ui?.page || manifest.options_page;
    expect(optionsPage).toBeTruthy();

    const options = await background.evaluate(async (pagePath) => {
      const url = chrome.runtime.getURL(pagePath);
      const response = await fetch(url);
      return {
        ok: response.ok,
        status: response.status,
        url,
        text: await response.text()
      };
    }, optionsPage);
    expect(options.url).toBe(`chrome-extension://${extensionId}/${optionsPage}`);
    expect(options.ok, `failed to fetch ${options.url}: ${options.status}`).toBeTruthy();
    expect(options.text).toContain('<html');
  } finally {
    await context.close();
  }
});
