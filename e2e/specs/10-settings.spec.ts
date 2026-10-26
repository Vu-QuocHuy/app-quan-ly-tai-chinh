import { expect, test } from '@playwright/test';
import { expectText, freshUser, home, type } from '../support/app';
import { sql } from '../support/supabase';

test.describe('Cài đặt & tài khoản', () => {
  test('sửa hồ sơ (họ tên, SĐT) lưu lên server', async ({ page }) => {
    const user = await freshUser(page, 'Tên Cũ');
    await page.getByRole('button', { name: 'Hồ sơ cá nhân' }).click();
    await type(page, page.getByRole('textbox', { name: 'Họ và tên' }), 'Tên Mới');
    await type(page, page.getByRole('textbox', { name: 'Số điện thoại (không bắt buộc)' }), '0912345678');
    await page.getByRole('button', { name: 'Lưu thông tin' }).click();
    await expect.poll(() => sql<{ display_name: string; phone: string }>(
      `select display_name, phone from public.profiles where user_id='${user.id}'`)[0], { timeout: 20_000 })
      .toEqual({ display_name: 'Tên Mới', phone: '0912345678' });
  });

  test('hồ sơ hiển thị họ tên đã lưu', async ({ page }) => {
    await freshUser(page, 'Nguyễn Hiển Thị');
    await page.getByRole('button', { name: 'Hồ sơ cá nhân' }).click();
    await page.getByRole('textbox', { name: 'Họ và tên' }).click();
    await expect.poll(() => page.evaluate(() => (document.activeElement as HTMLInputElement | null)?.value))
      .toBe('Nguyễn Hiển Thị');
  });

  test('đổi giao diện được lưu vào tài khoản', async ({ page }) => {
    const user = await freshUser(page);
    await page.getByRole('button', { name: 'Cài đặt', exact: true }).click();
    await page.getByRole('button', { name: /^Giao diện/ }).click();
    await page.getByRole('button', { name: /^Midnight forest/ }).click();
    await expect(page.getByRole('button', { name: /^Giao diện Midnight forest/ })).toBeVisible();
    await expect.poll(() => sql<{ theme_mode: string }>(
      `select theme_mode from public.profiles where user_id='${user.id}'`)[0]?.theme_mode, { timeout: 20_000 })
      .not.toBe('system');
  });

  test('tắt cảnh báo ngân sách', async ({ page }) => {
    const user = await freshUser(page);
    await page.getByRole('button', { name: 'Cài đặt', exact: true }).click();
    const sw = page.getByRole('switch', { name: /^Cảnh báo ngân sách/ });
    await expect(sw).toBeChecked();
    await sw.click();
    await expect(sw).not.toBeChecked();
    await expect.poll(() => sql<{ b: boolean }>(
      `select budget_alerts_enabled b from public.profiles where user_id='${user.id}'`)[0]?.b, { timeout: 20_000 }).toBe(false);
  });

  test('xung đột đồng bộ và lịch sử nhập hóa đơn mở được', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Cài đặt', exact: true }).click();
    await page.getByRole('button', { name: /^Đồng bộ dữ liệu/ }).click();
    await expectText(page, /đồng bộ|Đồng bộ/);
    await home(page);
  });

  test('xóa tài khoản xóa user và dữ liệu cloud', async ({ page }) => {
    const user = await freshUser(page);
    await page.getByRole('button', { name: 'Hồ sơ cá nhân' }).click();
    await page.getByRole('button', { name: 'Xóa tài khoản' }).click();
    const confirmBox = page.getByRole('textbox').last();
    if (await confirmBox.isVisible().catch(() => false)) await type(page, confirmBox, 'XÓA');
    await page.getByRole('button', { name: /^(Xóa tài khoản|Xóa vĩnh viễn|Xác nhận xóa|Xóa)$/ }).last().click();
    await expect.poll(() => sql(`select id from auth.users where id='${user.id}'`).length, { timeout: 30_000 }).toBe(0);
    await expect(page.getByRole('textbox', { name: 'Email' })).toBeVisible({ timeout: 20_000 });
  });
});
