import { expect, test, type Page } from '@playwright/test';
import { expectText, freshUser, open, syncNow, type, vnd } from '../support/app';
import { sql } from '../support/supabase';

async function addTransaction(page: Page, kind: 'thu' | 'chi', amount: number, note: string, category?: string) {
  if (!(await page.getByRole('button', { name: 'Thêm thu/chi' }).isVisible())) await open(page, '/');
  await page.getByRole('button', { name: 'Thêm thu/chi' }).click();
  await page.getByRole('button', { name: kind === 'thu' ? 'Thêm khoản thu' : 'Thêm khoản chi' }).click();
  await type(page, page.getByRole('textbox', { name: 'Số tiền (₫)' }), String(amount));
  await page.getByRole('button', { name: 'Danh mục', exact: true }).click();
  await page.getByRole('menuitem', { name: category ?? (kind === 'thu' ? 'Chưa phân loại' : 'Khác') }).click();
  await type(page, page.getByRole('textbox', { name: 'Nội dung' }), note);
  await page.getByRole('button', { name: 'Lưu giao dịch' }).click();
  await expect(page.getByRole('button', { name: 'Lưu giao dịch' })).toBeHidden();
}

/** Polls the server until the outbox has pushed what the UI shows. */
async function serverRow<T>(query: string, page?: Page) {
  if (page) await syncNow(page);
  let rows: T[] = [];
  await expect.poll(() => (rows = sql<T>(query)).length, { timeout: 30_000, message: query }).toBeGreaterThan(0);
  return rows[0];
}

test.describe('Thêm / sửa / xóa thu chi', () => {
  test('thêm khoản chi: hiện ở tổng quan, lịch sử và lên server', async ({ page }) => {
    const user = await freshUser(page);
    await addTransaction(page, 'chi', 125000, 'Ăn trưa văn phòng', 'Ăn uống');
    await open(page, '/');
    await expectText(page, `Chi tiêu tháng này - ${vnd(125000)}`);
    await open(page, '/invoices');
    await expectText(page, /Ăn trưa văn phòng|Ăn uống, \d{2}\/\d{2}\/\d{4}, chi 125\.000 ₫/);
    const row = await serverRow<{ total_minor: number; category_id: string }>(
      `select total_minor, category_id from public.invoices where user_id='${user.id}'`, page);
    expect(Number(row.total_minor)).toBe(125000);
    expect(row.category_id).toBe('food');
  });

  test('thêm khoản thu: cộng vào thu nhập và lên server', async ({ page }) => {
    const user = await freshUser(page);
    await addTransaction(page, 'thu', 15000000, 'Lương tháng');
    await open(page, '/');
    await expectText(page, `Thu nhập tháng này + ${vnd(15000000)}`);
    const row = await serverRow<{ amount_minor: number; note: string }>(
      `select amount_minor, note from public.income_entries where user_id='${user.id}'`, page);
    expect(Number(row.amount_minor)).toBe(15000000);
    expect(row.note).toBe('Lương tháng');
  });

  test('không cho lưu khi số tiền trống', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Thêm thu/chi' }).click();
    await page.getByRole('button', { name: 'Lưu giao dịch' }).click();
    await expect(page.getByRole('button', { name: 'Lưu giao dịch' })).toBeVisible();
    await expectText(page, /số tiền/i);
  });

  test('nút "Trợ lý AI" không che nút "Lưu giao dịch"', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Thêm thu/chi' }).click();
    const save = await page.getByRole('button', { name: 'Lưu giao dịch' }).boundingBox();
    const fab = await page.getByRole('button', { name: 'Trợ lý AI' }).boundingBox();
    const overlap = save && fab && fab.x < save.x + save.width && save.x < fab.x + fab.width
      && fab.y < save.y + save.height && save.y < fab.y + fab.height;
    expect(overlap, `save=${JSON.stringify(save)} fab=${JSON.stringify(fab)}`).toBeFalsy();
  });

  test('sửa khoản chi: lưu đúng số tiền mới, lên server', async ({ page }) => {
    const user = await freshUser(page);
    await addTransaction(page, 'chi', 50000, 'Gửi xe', 'Di chuyển');
    await page.getByRole('button', { name: /^Lịch sử thu chi/ }).click();
    await page.getByRole('button', { name: /chi 50\.000 ₫/ }).first().click();
    await page.getByRole('button', { name: 'Chỉnh sửa' }).click();
    await type(page, page.getByRole('textbox', { name: 'Số tiền *' }), '65000');
    await page.getByRole('button', { name: 'Cập nhật khoản chi' }).click();
    await expect(page.getByRole('heading', { name: 'Chi tiết khoản chi' })).toBeVisible();
    await page.getByRole('button', { name: 'Quay lại' }).click();
    await expect(page.getByRole('heading', { name: 'Lịch sử thu chi' })).toBeVisible();
    await expect(page.getByRole('button', { name: /chi 65\.000 ₫/ })).toBeVisible();
    await syncNow(page);
    await expect.poll(() => Number(sql<{ t: number }>(
      `select total_minor t from public.invoices where user_id='${user.id}'`)[0]?.t), { timeout: 30_000 }).toBe(65000);
  });

  test('màn chi tiết hiển thị số tiền mới ngay sau khi sửa', async ({ page }) => {
    await freshUser(page);
    await addTransaction(page, 'chi', 50000, 'Gửi xe', 'Di chuyển');
    await page.getByRole('button', { name: /^Lịch sử thu chi/ }).click();
    await page.getByRole('button', { name: /chi 50\.000 ₫/ }).first().click();
    await page.getByRole('button', { name: 'Chỉnh sửa' }).click();
    await type(page, page.getByRole('textbox', { name: 'Số tiền *' }), '65000');
    await page.getByRole('button', { name: 'Cập nhật khoản chi' }).click();
    await expect(page.getByRole('heading', { name: 'Chi tiết khoản chi' })).toBeVisible();
    await expectText(page, `Số tiền ${vnd(65000)}`);
  });

  test('xóa khoản chi: biến mất và tombstone trên server', async ({ page }) => {
    const user = await freshUser(page);
    await addTransaction(page, 'chi', 33000, 'Nước uống');
    await serverRow(`select id from public.invoices where user_id='${user.id}'`, page);
    await open(page, '/invoices');
    await page.getByRole('button', { name: /chi 33\.000 ₫/ }).first().click();
    await page.getByRole('button', { name: 'Xóa khoản chi' }).click();
    await page.getByRole('button', { name: /^(Xóa|Xác nhận xóa|Đồng ý)$/ }).last().click();
    await open(page, '/');
    await expectText(page, `Chi tiêu tháng này - ${vnd(0)}`);
    await syncNow(page);
    await expect.poll(() => sql<{ d: string | null }>(
      `select deleted_at d from public.invoices where user_id='${user.id}'`)[0]?.d, { timeout: 30_000 }).not.toBeNull();
  });

  test('dữ liệu theo tài khoản: thiết bị thứ hai thấy khoản chi đã thêm', async ({ page, browser }) => {
    const user = await freshUser(page);
    await addTransaction(page, 'chi', 222000, 'Đồng bộ thiết bị');
    await serverRow(`select id from public.invoices where user_id='${user.id}'`, page);
    const other = await browser.newPage();
    const { login } = await import('../support/app');
    await login(other, user);
    await expectText(other, `Chi tiêu tháng này - ${vnd(222000)}`, 45_000);
    await other.close();
  });
});
