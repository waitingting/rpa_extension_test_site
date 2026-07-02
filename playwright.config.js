const { defineConfig } = require('@playwright/test');

const serverTimeout = 30 * 1000;

module.exports = defineConfig({
  testDir: './tests/browser_e2e',
  timeout: 60 * 1000,
  expect: {
    timeout: 10 * 1000
  },
  reporter: process.env.CI ? 'line' : [['list']],
  use: {
    headless: false,
    trace: 'retain-on-failure'
  },
  webServer: [
    {
      command: 'npx http-server sites/extension-fixtures/main -a 127.0.0.1 -p 8007 -c-1 --cors',
      url: 'http://127.0.0.1:8007/',
      reuseExistingServer: true,
      timeout: serverTimeout
    },
    {
      command: 'npx http-server sites/extension-fixtures/cross-a -a 127.0.0.1 -p 8008 -c-1 --cors',
      url: 'http://127.0.0.1:8008/',
      reuseExistingServer: true,
      timeout: serverTimeout
    },
    {
      command: 'npx http-server sites/extension-fixtures/cross-b -a 127.0.0.1 -p 8009 -c-1 --cors',
      url: 'http://127.0.0.1:8009/',
      reuseExistingServer: true,
      timeout: serverTimeout
    }
  ]
});
