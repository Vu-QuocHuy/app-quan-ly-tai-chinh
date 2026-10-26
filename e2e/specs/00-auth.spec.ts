import { expect, test } from '@playwright/test';
import { expectText, login, ready, type } from '../support/app';
import { createUser, sql } from '../support/supabase';

test.describe('Đăng nhập / đăng ký', () => {
  test('sai mật khẩu báo lỗi, không vào app', async ({ page }) => {
    const user = await createUser(`bad-${Date.now()}@e2e.test`, '');
    await page.goto('/');
    await ready(page);
    await type(page, page.getByRole('textbox', { name: 'Email' }), user.email);
    await type(page, page.getByRole('textbox', { name: 'Mật khẩu' }), 'sai-mat-khau-123');
    await page.getByRole('button', { name: 'Đăng nhập', exact: true }).last().click();
    await expectText(page, /không đúng|không hợp lệ|Invalid|sai/i);
    await expect(page.getByRole('button', { name: 'Cài đặt' })).toBeHidden();
  });

  test('bỏ trống email/mật khẩu hiện lỗi kiểm tra', async ({ page }) => {
    await page.goto('/');
    await ready(page);
    await page.getByRole('button', { name: 'Đăng nhập', exact: true }).last().click();
    await expectText(page, /Hãy nhập email|nhập email/i);
    await expectText(page, 'Hãy nhập mật khẩu.');
  });

  test('đăng ký tài khoản mới rồi vào được app', async ({ page }) => {
    const email = `signup-${Date.now()}@e2e.test`;
    await page.goto('/');
    await ready(page);
    await page.getByRole('button', { name: 'Đăng ký', exact: true }).first().click();
    const textboxes = page.getByRole('textbox');
    await expect(textboxes.first()).toBeVisible();
    for (const box of await textboxes.all()) {
      const name = (await box.getAttribute('aria-label')) ?? (await box.textContent()) ?? '';
      if (/email/i.test(name)) await type(page, box, email);
      else if (/mật khẩu/i.test(name)) await type(page, box, 'E2e-Signup-2026!');
      else if (/tên|họ/i.test(name)) await type(page, box, 'Người Đăng Ký');
    }
    await page.getByRole('button', { name: /^(Đăng ký|Tạo tài khoản)$/ }).last().click();
    await expect(page.getByRole('button', { name: 'Cài đặt' })).toBeVisible({ timeout: 45_000 });
    expect(sql(`select id from auth.users where email='${email}'`)).toHaveLength(1);
  });

  test('đăng xuất quay về màn đăng nhập', async ({ page }) => {
    const user = await createUser(`logout-${Date.now()}@e2e.test`, 'Đăng Xuất');
    await login(page, user);
    await page.getByRole('button', { name: 'Hồ sơ cá nhân' }).click();
    await page.getByRole('button', { name: 'Đăng xuất' }).click();
    const confirm = page.getByRole('button', { name: 'Đăng xuất' }).last();
    if (await confirm.isVisible()) await confirm.click();
    await expect(page.getByRole('textbox', { name: 'Email' })).toBeVisible({ timeout: 20_000 });
  });
});
