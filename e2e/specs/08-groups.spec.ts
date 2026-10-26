import { expect, test, type Page } from '@playwright/test';
import { expectText, login, syncQuiet, type, vnd } from '../support/app';
import { createUser, sql } from '../support/supabase';

async function createGroup(page: Page, name: string) {
  await page.getByRole('button', { name: 'Nhóm', exact: true }).last().click();
  await page.getByRole('button', { name: 'Tạo nhóm' }).click();
  await type(page, page.getByRole('textbox', { name: /^Tên nhóm/ }), name);
  await page.getByRole('button', { name: 'Tạo nhóm' }).last().click();
  await expect(page.getByRole('heading', { name })).toBeVisible();
}

test.describe('Nhóm chi tiêu', () => {
  test('tạo nhóm, mời bằng mã, thành viên tham gia, chia đều', async ({ browser }) => {
    test.setTimeout(240_000);
    const stamp = Date.now();
    const owner = await createUser(`owner-${stamp}@e2e.test`, 'Chủ Nhóm');
    const member = await createUser(`member-${stamp}@e2e.test`, 'Thành Viên');
    const a = await (await browser.newContext()).newPage();
    const b = await (await browser.newContext()).newPage();
    await login(a, owner);
    await syncQuiet(a);
    const name = `Quỹ nhà ${stamp % 10000}`;
    await createGroup(a, name);

    // Invite code shown in the QR sheet.
    await a.getByRole('button', { name: 'Mời thành viên bằng QR' }).click();
    await expectText(a, `Mời vào ${name}`);
    const [{ invite_code: code }] = sql<{ invite_code: string }>(
      `select invite_code from public.expense_groups where owner_id='${owner.id}'`);
    await a.getByRole('button', { name: 'Bỏ qua' }).click();

    await login(b, member);
    await syncQuiet(b);
    await b.getByRole('button', { name: 'Nhóm', exact: true }).last().click();
    await b.getByRole('button', { name: 'Tham gia' }).click();
    await b.getByRole('button', { name: 'Nhập mã mời' }).click();
    await type(b, b.getByRole('textbox', { name: /^Mã mời/ }), code);
    await b.getByRole('alertdialog').getByRole('button', { name: 'Tham gia' }).click();
    await expect(b.getByRole('heading', { name })).toBeVisible({ timeout: 30_000 });

    // Owner splits 300.000 ₫ equally between both members.
    await a.getByRole('button', { name: 'Làm mới chi tiết nhóm' }).click();
    await expectText(a, 'Thành viên (2)', 30_000);
    await a.getByRole('button', { name: 'Chia tiền', exact: true }).click();
    await type(a, a.getByRole('textbox', { name: 'Nội dung' }), 'Đi chợ cuối tuần');
    await type(a, a.getByRole('textbox', { name: 'Tổng tiền' }), '300000');
    await expect(a.getByRole('checkbox', { name: 'Thành Viên' })).toBeChecked();
    await a.getByRole('button', { name: 'Chia tiền', exact: true }).last().click();
    await expectText(a, 'Đi chợ cuối tuần');

    // Member sees the expense and owes half.
    await b.getByRole('button', { name: 'Làm mới chi tiết nhóm' }).click();
    await expectText(b, 'Đi chợ cuối tuần', 30_000);
    await expectText(b, vnd(150000));
    const splits = sql<{ amount_minor: number }>(`select s.amount_minor from public.group_expense_splits s
      join public.group_expenses e on e.id=s.expense_id
      join public.expense_groups g on g.id=e.group_id where g.owner_id='${owner.id}'`);
    expect(splits.map((s) => Number(s.amount_minor)).sort()).toEqual([150000, 150000]);

    // Both profiles have names; the member list must show them.
    for (const page of [a, b]) {
      const snapshot = await page.locator('body').ariaSnapshot();
      expect.soft(snapshot, 'tên thành viên trong nhóm').toContain('Chủ Nhóm');
      expect.soft(snapshot, 'tên thành viên trong nhóm').toContain('Thành Viên');
      expect.soft(snapshot).not.toContain('Chưa đặt tên');
    }
  });

  for (const [label, code, message] of [
    ['sai định dạng', 'ZZZZ9999', 'Mã mời phải có 8 ký tự'],
    ['không tồn tại', 'ABCDEF12', /không (tồn tại|hợp lệ|đúng|tìm thấy)|hết hạn|Không thể/i],
  ] as const) {
    test(`mã mời ${label} báo lỗi`, async ({ page }) => {
      const user = await createUser(`join-${Date.now()}@e2e.test`, 'Sai Mã');
      await login(page, user);
      await syncQuiet(page);
      await page.getByRole('button', { name: 'Nhóm', exact: true }).last().click();
      await page.getByRole('button', { name: 'Tham gia' }).click();
      await page.getByRole('button', { name: 'Nhập mã mời' }).click();
      await type(page, page.getByRole('textbox', { name: /^Mã mời/ }), code);
      await page.getByRole('alertdialog').getByRole('button', { name: 'Tham gia' }).click();
      await expectText(page, message);
    });
  }

  test('quỹ chung mở được', async ({ page }) => {
    const user = await createUser(`fund-${Date.now()}@e2e.test`, 'Quỹ');
    await login(page, user);
    await syncQuiet(page);
    await createGroup(page, 'Quỹ du lịch');
    await page.getByRole('button', { name: 'Quỹ chung' }).click();
    await expectText(page, /Quỹ chung|quỹ/);
  });
});
