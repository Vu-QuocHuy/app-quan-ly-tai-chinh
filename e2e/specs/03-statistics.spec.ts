import { expect, test } from '@playwright/test';
import { DEMO_STATE, demo, expectText, monthKey, start, vnd } from '../support/app';
import { monthTotals, yearTotals } from '../support/expected';
import { sql } from '../support/supabase';

test.use({ storageState: DEMO_STATE });

test.describe('Thống kê', () => {
  test('theo tháng khớp server (3 tháng gần nhất)', async ({ page }) => {
    await start(page, '/statistics');
    for (const offset of [0, -1, -2]) {
      if (offset < 0) await page.getByRole('button', { name: 'Tháng trước' }).click();
      const t = monthTotals(demo().id, monthKey(offset));
      await expectText(page, `Tổng thu ${vnd(t.thu)}`);
      await expectText(page, `Tổng chi ${vnd(t.chi)}`);
      await expectText(page, `Chênh lệch thu − chi ${vnd(t.net)}`);
    }
  });

  test('lịch ngày: chạm ngày 5 lọc tổng theo ngày, "Xem toàn tháng" trả lại', async ({ page }) => {
    const day = `${monthKey()}-05`;
    const [d] = sql<{ chi: number; thu: number }>(`select
      (select coalesce(sum(total_minor),0) from public.invoices where user_id='${demo().id}' and status='confirmed'
        and (issued_at at time zone 'Asia/Ho_Chi_Minh')::date='${day}')::bigint chi,
      (select coalesce(sum(amount_minor),0) from public.income_entries where user_id='${demo().id}'
        and (received_at at time zone 'Asia/Ho_Chi_Minh')::date='${day}')::bigint thu`);
    await start(page, '/statistics');
    await page.getByRole('button', { name: /^Ngày 5,/ }).click();
    const [y, m] = monthKey().split('-');
    await expectText(page, `Ngày 05/${m}/${y} ↓ Tổng thu ${vnd(Number(d.thu))} ↑ Tổng chi ${vnd(Number(d.chi))}`);
    await page.getByRole('button', { name: 'Xem toàn tháng' }).click();
    await expectText(page, `Tháng ${m}/${y}`);
  });

  test('theo năm khớp server, năm trước cũng đúng', async ({ page }) => {
    const year = new Date().getFullYear();
    await start(page, '/statistics');
    await page.getByRole('button', { name: 'Theo năm' }).click();
    let t = yearTotals(demo().id, year);
    await expectText(page, `Tổng thu ${vnd(t.thu)}`);
    await expectText(page, `Tổng chi ${vnd(t.chi)}`);
    await page.getByRole('button', { name: 'Năm trước' }).click();
    t = yearTotals(demo().id, year - 1);
    await expectText(page, `Năm ${year - 1}`);
    await expectText(page, `Tổng chi ${vnd(t.chi)}`);
  });

  test('biểu đồ phân bổ có danh mục chi lớn nhất', async ({ page }) => {
    await start(page, '/statistics');
    await page.getByRole('button', { name: 'Theo năm' }).click();
    await expectText(page, /Biểu đồ tròn chi tiêu/);
    await expectText(page, /Nhà ở, \d+%/);
  });

  test('nút xuất báo cáo mở lựa chọn PDF/CSV', async ({ page }) => {
    await start(page, '/statistics');
    await page.getByRole('button', { name: 'Xuất báo cáo' }).click();
    await expect(page.getByRole('button', { name: /^Báo cáo PDF/ })).toBeVisible();
    await expect(page.getByRole('button', { name: /^Báo cáo CSV/ })).toBeVisible();
  });
});
