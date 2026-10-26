import { expect, test } from '@playwright/test';
import { DEMO_STATE, expectText, freshUser, start, syncNow, type, vnd } from '../support/app';
import { sql } from '../support/supabase';

test.describe('Thu chi định kỳ & mục tiêu', () => {
  test('thêm khoản chi cố định hàng tháng', async ({ page }) => {
    const user = await freshUser(page);
    await page.getByRole('button', { name: 'Thu chi định kỳ' }).click();
    await page.getByRole('button', { name: 'Thêm khoản định kỳ' }).click();
    await page.getByRole('button', { name: 'Khoản chi định kỳ' }).click();
    await type(page, page.getByRole('textbox', { name: 'Tên khoản' }), 'Tiền nhà');
    await type(page, page.getByRole('textbox', { name: 'Số tiền' }), '5000000');
    await page.getByRole('button', { name: 'Lưu', exact: true }).click();
    await expectText(page, 'Tiền nhà');
    await expectText(page, vnd(5000000));
    await syncNow(page);
    await expect.poll(() => sql(`select id from public.planning_entries where user_id='${user.id}'`).length, { timeout: 30_000 }).toBe(1);
  });

  test('thêm mục tiêu tiết kiệm', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Thu chi định kỳ' }).click();
    await page.getByRole('button', { name: 'Thêm khoản định kỳ' }).click();
    await page.getByRole('button', { name: 'Mục tiêu tiết kiệm' }).click();
    await type(page, page.getByRole('textbox', { name: 'Tên mục tiêu' }), 'Mua laptop');
    await type(page, page.getByRole('textbox', { name: 'Số tiền mục tiêu' }), '30000000');
    await page.getByRole('button', { name: 'Lưu', exact: true }).click();
    await expectText(page, 'Mua laptop');
    await expectText(page, vnd(30000000));
  });

  test.describe('có danh mục thu', () => {
    test.use({ storageState: DEMO_STATE });
    test('cho phép tạo "Khoản thu định kỳ" khi đã có danh mục thu', async ({ page }) => {
      await start(page, '/plans');
      await page.waitForTimeout(3000);
      await page.getByRole('button', { name: 'Thêm khoản định kỳ' }).click();
      await expect(page.getByRole('button', { name: 'Khoản thu định kỳ' })).toBeEnabled();
    });
  });
});
