import { expect, test } from '@playwright/test';
import { expectText, freshUser, home, monthKey, syncNow, type, vnd } from '../support/app';
import { sql } from '../support/supabase';

test.describe('Danh mục & ngân sách', () => {
  test('thêm danh mục chi kèm hạn mức', async ({ page }) => {
    const user = await freshUser(page);
    await page.getByRole('button', { name: 'Danh mục', exact: true }).click();
    await page.getByRole('button', { name: 'Thêm danh mục' }).click();
    await type(page, page.getByRole('textbox', { name: /^Tên danh mục/ }), 'Cà phê');
    await type(page, page.getByRole('textbox', { name: /^Hạn mức tháng/ }), '800000');
    await page.getByRole('checkbox', { name: 'Ăn uống Ăn uống' }).click();
    await page.getByRole('button', { name: 'Lưu danh mục' }).click();
    await expect(page.getByRole('button', { name: /^Cà phê Danh mục tùy chỉnh/ })).toBeVisible();
    await home(page);
    await page.getByRole('button', { name: 'Ngân sách', exact: true }).first().click();
    await expect(page.getByRole('progressbar', { name: /^Cà phê Hạn mức: 800\.000 ₫/ })
      .or(page.getByRole('group', { name: /^Cà phê Hạn mức: 800\.000 ₫/ }))).toBeAttached();
    await syncNow(page);
    await expect.poll(() => sql(`select c.name, b.limit_minor from public.categories c
      join public.budgets b on b.user_id=c.user_id and b.category_id=c.id
      where c.user_id='${user.id}' and c.name='Cà phê' and b.month_key='${monthKey()}'`).length, { timeout: 30_000 }).toBe(1);
  });

  test('sửa tên rồi xóa danh mục tùy chỉnh', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Danh mục', exact: true }).click();
    await page.getByRole('button', { name: 'Thêm danh mục' }).click();
    await type(page, page.getByRole('textbox', { name: /^Tên danh mục/ }), 'Tạm thời');
    await page.getByRole('button', { name: 'Lưu danh mục' }).click();
    const row = page.getByRole('button', { name: /^Tạm thời Danh mục tùy chỉnh/ });
    await row.getByRole('button', { name: 'Chỉnh sửa danh mục' }).click();
    await type(page, page.getByRole('textbox', { name: /^Tên danh mục/ }), 'Đã đổi tên');
    await page.getByRole('button', { name: 'Lưu danh mục' }).click();
    const renamed = page.getByRole('button', { name: /^Đã đổi tên Danh mục tùy chỉnh/ });
    await expect(renamed).toBeVisible();
    await renamed.getByRole('button', { name: 'Xóa danh mục' }).click();
    await page.getByRole('button', { name: /^(Xóa|Xóa danh mục|Đồng ý)$/ }).last().click();
    await expect(renamed).toBeHidden();
  });

  test('danh mục mặc định không có nút xóa', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Danh mục', exact: true }).click();
    const food = page.getByRole('button', { name: /^Ăn uống Danh mục mặc định/ });
    await expect(food).toBeVisible();
    await expect(food.getByRole('button', { name: 'Xóa danh mục' })).toHaveCount(0);
  });

  test('tab khoản thu có danh mục "Chưa phân loại"', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Danh mục', exact: true }).click();
    await page.getByRole('button', { name: 'Khoản thu', exact: true }).click();
    await expect(page.getByRole('button', { name: /^Chưa phân loại/ })).toBeVisible();
  });

  test('đặt hạn mức, vượt 80% hiện cảnh báo', async ({ page }) => {
    await freshUser(page);
    await page.getByRole('button', { name: 'Ngân sách', exact: true }).first().click();
    await page.getByRole('button', { name: 'Sửa ngân sách Ăn uống' }).click();
    await type(page, page.getByRole('textbox', { name: 'Hạn mức tháng' }), '100000');
    await page.getByRole('button', { name: 'Lưu', exact: true }).click();
    await expect(page.getByRole('progressbar', { name: /^Ăn uống Hạn mức: 100\.000 ₫ · Đã chi 0 ₫/ })).toBeAttached();
    await home(page);
    await page.getByRole('button', { name: 'Thêm thu/chi' }).click();
    await page.getByRole('button', { name: 'Thêm khoản chi' }).click();
    await type(page, page.getByRole('textbox', { name: 'Số tiền (₫)' }), '90000');
    await page.getByRole('button', { name: 'Danh mục', exact: true }).click();
    await page.getByRole('menuitem', { name: 'Ăn uống' }).click();
    await page.getByRole('button', { name: 'Lưu giao dịch' }).click();
    await page.getByRole('button', { name: 'Ngân sách', exact: true }).first().click();
    await expect(page.getByRole('progressbar', { name: new RegExp(`^Ăn uống Hạn mức: 100\\.000 ₫ · Đã chi ${vnd(90000).replace('.', '\\.')} \\(90%\\)`) })).toBeAttached();
    await expectText(page, /vượt|80%|sắp hết|cảnh báo/i);
  });
});
