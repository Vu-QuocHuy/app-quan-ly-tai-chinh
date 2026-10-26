import { expect, test } from '@playwright/test';
import { DEMO_STATE, demo, expectText, names, start, type, vnd } from '../support/app';
import { sql } from '../support/supabase';

test.use({ storageState: DEMO_STATE });

const rows = (page: import('@playwright/test').Page) =>
  page.getByRole('button', { name: /, \d{2}\/\d{2}\/\d{4}, / });

test.describe('Lịch sử thu chi', () => {
  test('sắp xếp mới nhất trước', async ({ page }) => {
    await start(page, '/invoices');
    await expect(rows(page).first()).toBeVisible();
    const shown = (await names(rows(page))).slice(0, 8);
    const dates = shown.map((n) => n.match(/(\d{2})\/(\d{2})\/(\d{4})/)!).map(([, d, m, y]) => `${y}${m}${d}`);
    expect(dates, shown.join('\n')).toEqual([...dates].sort().reverse());
    const [latest] = sql<{ d: string }>(`select to_char(max(issued_at at time zone 'Asia/Ho_Chi_Minh'),'YYYYMMDD') d
      from public.invoices where user_id='${demo().id}' and status='confirmed'`);
    expect(dates[0] >= latest.d, `newest row ${dates[0]} vs server ${latest.d}`).toBeTruthy();
  });

  test('lọc chỉ khoản thu', async ({ page }) => {
    await start(page, '/invoices');
    await page.getByRole('button', { name: 'Khoản thu', exact: true }).click();
    await expect(rows(page).first()).toBeVisible();
    await expect.poll(async () => (await names(rows(page))).every((n) => n.includes('khoản thu'))).toBe(true);
    expect((await names(rows(page))).length).toBeGreaterThan(0);
  });

  test('tìm kiếm theo người bán', async ({ page }) => {
    await start(page, '/invoices');
    await type(page, page.getByRole('searchbox', { name: 'Tìm giao dịch thu hoặc chi' }), 'Highlands');
    await expect.poll(async () => {
      const shown = await names(rows(page));
      return shown.length > 0 && shown.every((n) => n.startsWith('Highlands Coffee'));
    }).toBe(true);
  });

  test('bộ lọc "Cần kiểm tra" chỉ hiện hóa đơn chờ duyệt', async ({ page }) => {
    const pending = sql<{ seller_name: string }>(`select seller_name from public.invoices
      where user_id='${demo().id}' and status='needsReview'`);
    await start(page, '/invoices');
    await page.getByRole('checkbox', { name: 'Cần kiểm tra' }).click();
    for (const p of pending) await expect(rows(page).filter({ hasText: '' }).and(page.getByRole('button', { name: new RegExp(`^${p.seller_name}`) }))).toBeVisible();
    await expect(rows(page)).toHaveCount(pending.length);
  });

  test('chi tiết khoản chi hiển thị đủ dòng hàng', async ({ page }) => {
    const [inv] = sql<{ id: string; seller_name: string; total_minor: number }>(`select id, seller_name, total_minor
      from public.invoices where user_id='${demo().id}' and status='confirmed' and seller_name='Tiền thuê nhà'
      order by issued_at desc limit 1`);
    const lines = sql<{ description: string }>(`select description from public.invoice_lines
      where user_id='${demo().id}' and invoice_id='${inv.id}'`);
    await start(page, '/invoices');
    await type(page, page.getByRole('searchbox', { name: 'Tìm giao dịch thu hoặc chi' }), 'Tiền thuê nhà');
    await expect.poll(async () => (await names(rows(page)))[0] ?? '').toMatch(/^Tiền thuê nhà/);
    await rows(page).first().click();
    await expect(page.getByRole('heading', { name: /^Chi tiết (khoản chi|hóa đơn)$/ })).toBeVisible();
    await expectText(page, `Số tiền ${vnd(Number(inv.total_minor))}`);
    for (const l of lines) await expectText(page, l.description);
  });
});
