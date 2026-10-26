import { test as setup } from '@playwright/test';
import { DEMO_STATE, demo, expectText, login, vnd } from '../support/app';
import { yearTotals } from '../support/expected';

// Logs the demo account in once, waits for the initial pull of ~1000 records
// to finish, and saves session + IndexedDB so read-only specs start warm.
setup('demo account synced', async ({ page }) => {
  setup.setTimeout(240_000);
  const user = demo();
  await login(page, user);
  const year = new Date().getFullYear();
  const expected = yearTotals(user.id, year);
  // Navigate by tapping, not by URL: see open() in support/app.ts.
  await page.getByRole('button', { name: 'Thống kê' }).click();
  await page.getByRole('button', { name: 'Theo năm' }).click();
  await expectText(page, `Tổng chi ${vnd(expected.chi)}`, 180_000);
  await page.context().storageState({ path: DEMO_STATE, indexedDB: true });
});
