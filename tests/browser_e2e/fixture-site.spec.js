const { test, expect } = require('@playwright/test');

const fixtureUrl = process.env.RPA_FIXTURE_URL || 'http://127.0.0.1:8007/';

test('fixture site supports common user actions', async ({ page }) => {
  await page.goto(fixtureUrl);

  await expect(page.locator('#page-title')).toHaveText('RPA Extension Full Fixture');
  await page.locator('#input-text').fill('edited text');
  await expect(page.locator('#input-text')).toHaveValue('edited text');

  await page.locator('#checkbox-b').check();
  await expect(page.locator('#checkbox-b')).toBeChecked();

  await page.locator('#select-single').selectOption('gamma');
  await expect(page.locator('#select-single')).toHaveValue('gamma');

  await page.locator('#textarea-main').fill('line a\nline b');
  await expect(page.locator('#textarea-main')).toHaveValue('line a\nline b');

  await page.locator('#open-dialog').click();
  await expect(page.locator('#fixture-dialog')).toBeVisible();
  await page.locator('#close-dialog').click();
  await expect(page.locator('#fixture-dialog')).not.toBeVisible();

  await page.locator('#add-row').click();
  await expect(page.locator('#dynamic-input-1')).toHaveValue('value 1');
});

test('fixture site exposes same-origin and cross-origin frames', async ({ page }) => {
  await page.goto(fixtureUrl);

  const sameOrigin = page.frameLocator('#same-origin-frame');
  await expect(sameOrigin.locator('#same-frame-title')).toBeVisible();

  const crossOrigin = page.frameLocator('#cross-origin-frame');
  await expect(crossOrigin.locator('body')).toContainText('Cross Origin');
});
