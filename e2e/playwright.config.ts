import { defineConfig } from '@playwright/test';

// Flutter web E2E against a local Supabase stack. See e2e/README.md.
export default defineConfig({
  testDir: './specs',
  outputDir: './test-results',
  timeout: 90_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 2,
  retries: 0,
  globalSetup: './global-setup.ts',
  reporter: [
    ['list'],
    ['html', { outputFolder: './playwright-report', open: 'never' }],
    ['json', { outputFile: './test-results/results.json' }],
  ],
  use: {
    // Phone-sized viewport without touch emulation: Flutter's mobile text
    // input strategy drops Playwright fills.
    viewport: { width: 412, height: 915 },
    channel: 'chrome',
    baseURL: 'http://127.0.0.1:8091',
    locale: 'vi-VN',
    timezoneId: 'Asia/Ho_Chi_Minh',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    actionTimeout: 15_000,
  },
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    { name: 'e2e', testMatch: /.*\.spec\.ts/, dependencies: ['setup'] },
  ],
  webServer: {
    command: 'python3 -m http.server 8091 --bind 127.0.0.1 --directory ../build/web-e2e',
    url: 'http://127.0.0.1:8091',
    reuseExistingServer: true,
  },
});
