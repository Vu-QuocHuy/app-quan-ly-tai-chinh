import { expect, test } from '@playwright/test';
import { DEMO_STATE, demo, expectText, monthKey, start, type, vnd } from '../support/app';
import { monthTotals } from '../support/expected';

test.use({ storageState: DEMO_STATE });

test.describe('Trợ lý tài chính (offline)', () => {
  test('"Tháng này tôi đã chi bao nhiêu?" khớp server', async ({ page }) => {
    const t = monthTotals(demo().id, monthKey());
    await start(page, '/chat');
    await page.getByRole('checkbox', { name: 'Tháng này tôi đã chi bao nhiêu?' }).click();
    await expectText(page, `ghi nhận ${t.n} hóa đơn, tổng chi ${vnd(t.chi)}`);
  });

  test('"Tháng này tôi đã thu bao nhiêu?" khớp server', async ({ page }) => {
    const t = monthTotals(demo().id, monthKey());
    await start(page, '/chat');
    await page.getByRole('checkbox', { name: 'Tháng này tôi đã thu bao nhiêu?' }).click();
    await expectText(page, vnd(t.thu));
  });

  test('so sánh với tháng trước nêu đúng 2 con số', async ({ page }) => {
    const now = monthTotals(demo().id, monthKey());
    const prev = monthTotals(demo().id, monthKey(-1));
    await start(page, '/chat');
    await page.getByRole('checkbox', { name: 'So sánh chi tiêu tháng này với tháng trước' }).click();
    await expectText(page, vnd(now.chi));
    await expectText(page, vnd(prev.chi));
  });

  test('gõ câu hỏi tự do và gửi', async ({ page }) => {
    await start(page, '/chat');
    await type(page, page.getByRole('textbox', { name: 'Nhắn trợ lý' }), 'Danh mục nào tôi chi nhiều nhất tháng này?');
    await expect(page.getByRole('button', { name: 'Gửi câu hỏi' }).last()).toBeEnabled();
    await page.getByRole('button', { name: 'Gửi câu hỏi' }).last().click();
    await expectText(page, 'Bạn: Danh mục nào tôi chi nhiều nhất tháng này?');
    await expectText(page, /Trợ lý: (?!Xin chào)/, 20_000);
  });
});
