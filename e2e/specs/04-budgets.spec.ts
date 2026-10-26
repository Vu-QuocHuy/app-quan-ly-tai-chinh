import { expect, test } from '@playwright/test';
import { DEMO_STATE, demo, monthKey, scrollTo, start, vnd } from '../support/app';
import { sql } from '../support/supabase';

test.use({ storageState: DEMO_STATE });

test.describe('Ngân sách (dữ liệu demo)', () => {
  test('hạn mức và số đã chi từng danh mục khớp server', async ({ page }) => {
    const budgets = sql<{ name: string; limit_minor: number; spent: number }>(`
      select c.name, b.limit_minor, coalesce((select sum(i.total_minor) from public.invoices i
        where i.user_id=b.user_id and i.category_id=b.category_id and i.status='confirmed'
          and to_char(i.issued_at at time zone 'Asia/Ho_Chi_Minh','YYYY-MM')=b.month_key),0)::bigint spent
      from public.budgets b join public.categories c on c.user_id=b.user_id and c.id=b.category_id
      where b.user_id='${demo().id}' and b.month_key='${monthKey()}'`);
    expect(budgets.length).toBeGreaterThan(0);
    await start(page, '/budgets');
    for (const b of budgets) {
      const bar = page.getByRole('progressbar', { name: new RegExp(`^${b.name} Hạn mức: ${vnd(Number(b.limit_minor)).replace(/\./g, '\\.')} · Đã chi ${vnd(Number(b.spent)).replace(/\./g, '\\.')}`) });
      await scrollTo(page, bar);
    }
  });

  test('chuyển tháng trước/sau', async ({ page }) => {
    await start(page, '/budgets');
    const [y, m] = monthKey(-1).split('-').map(Number);
    await page.getByRole('button', { name: 'Tháng trước' }).click();
    await expect(page.getByRole('button', { name: `Tháng ${String(m).padStart(2, '0')}/${y}`, exact: true })).toBeVisible();
  });
});
