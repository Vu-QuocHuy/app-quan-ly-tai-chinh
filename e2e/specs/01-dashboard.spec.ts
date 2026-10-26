import { expect, test } from '@playwright/test';
import { DEMO_STATE, demo, expectText, monthKey, start, vnd } from '../support/app';
import { monthTotals } from '../support/expected';
import { sql } from '../support/supabase';

test.use({ storageState: DEMO_STATE });

test.describe('Tổng quan', () => {
  test('số dư, thu, chi tháng này khớp dữ liệu server', async ({ page }) => {
    const t = monthTotals(demo().id, monthKey());
    await start(page);
    await expectText(page, `Tổng số dư ${vnd(t.net)}`);
    await expectText(page, `Thu nhập tháng này + ${vnd(t.thu)}`);
    await expectText(page, `Chi tiêu tháng này - ${vnd(t.chi)}`);
  });

  test('chi tiêu hôm nay khớp server và mở được chi tiết ngày', async ({ page }) => {
    const [today] = sql<{ chi: number; n: number }>(`
      select coalesce(sum(total_minor),0)::bigint chi, count(*)::int n from public.invoices
      where user_id = '${demo().id}' and status = 'confirmed'
        and (issued_at at time zone 'Asia/Ho_Chi_Minh')::date = (now() at time zone 'Asia/Ho_Chi_Minh')::date`);
    await start(page);
    await expectText(page, `Đã chi ${vnd(Number(today.chi))}`);
    await page.getByRole('button', { name: /^Chi tiêu hôm nay/ }).click();
    await expectText(page, /Thu chi ngày \d{2}\/\d{2}\/\d{4}/);
    await expectText(page, `Khoản chi (${today.n})`);
  });

  test('ẩn/hiện số tiền', async ({ page }) => {
    const t = monthTotals(demo().id, monthKey());
    await start(page);
    await page.getByRole('button', { name: 'Ẩn số tiền' }).click();
    await expect(page.getByRole('button', { name: 'Hiện số tiền' })).toBeVisible();
    await expect.poll(() => page.locator('body').ariaSnapshot()).not.toContain(vnd(t.net));
    await page.getByRole('button', { name: 'Hiện số tiền' }).click();
    await expectText(page, `Tổng số dư ${vnd(t.net)}`);
  });

  test('đổi sang tháng trước cập nhật số liệu', async ({ page }) => {
    const prev = monthTotals(demo().id, monthKey(-1));
    await start(page);
    await page.getByRole('button', { name: /^Tháng \d+, \d{4}$/ }).click();
    const [y, m] = monthKey(-1).split('-').map(Number);
    if (y !== new Date().getFullYear()) await page.getByRole('button', { name: 'Năm trước' }).click();
    await page.getByRole('button', { name: `Th ${m}`, exact: true }).click();
    await expectText(page, `Tháng ${m}, ${y}`);
    await expectText(page, `Chi tiêu tháng này - ${vnd(prev.chi)}`);
  });

  test('giao dịch gần đây hiển thị giao dịch mới nhất', async ({ page }) => {
    const [latest] = sql<{ seller_name: string }>(`
      select seller_name from public.invoices where user_id = '${demo().id}' and status = 'confirmed'
      order by issued_at desc limit 1`);
    await start(page);
    const recent = page.getByRole('button', { name: /Khoản chi đã lưu$/ }).first();
    await expect(recent).toHaveAccessibleName(new RegExp(`^${latest.seller_name}`));
  });

  test('tiện ích mở đúng màn hình', async ({ page }) => {
    await start(page);
    for (const [button, heading] of [
      ['Thống kê', 'Thống kê thu chi'],
      ['Thu chi định kỳ', 'Thu chi định kỳ'],
      ['Ngân sách', 'Hạn mức ngân sách'],
      ['Danh mục', 'Quản lý danh mục'],
    ] as const) {
      await page.getByRole('button', { name: button, exact: true }).first().click();
      await expect(page.getByRole('heading', { name: heading })).toBeVisible();
      await page.getByRole('button', { name: /^(Quay lại|Về Tổng quan)$/ }).click();
    }
  });
});
