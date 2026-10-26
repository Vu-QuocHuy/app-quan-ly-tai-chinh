import { expect, test } from '@playwright/test';
import { DEMO_STATE, expectText, start } from '../support/app';

test.use({ storageState: DEMO_STATE });

test.describe('Quét & xuất báo cáo', () => {
  test('không có camera: báo rõ và cho chọn ảnh QR từ thư viện', async ({ page }) => {
    await start(page);
    await page.getByRole('button', { name: 'Quét QR thanh toán hoặc hóa đơn' }).click();
    await expect(page.getByRole('heading', { name: 'Quét' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Chọn ảnh QR từ thư viện' })).toBeVisible();
  });

  test('thông báo lỗi camera bằng tiếng Việt', async ({ page }) => {
    await start(page);
    await page.getByRole('button', { name: 'Quét QR thanh toán hoặc hóa đơn' }).click();
    await expect.poll(() => page.locator('body').ariaSnapshot()).not.toMatch(/Scanning is not supported|NotFoundError/);
  });

  test('tab Hóa đơn có lựa chọn chụp/chọn ảnh', async ({ page }) => {
    await start(page);
    await page.getByRole('button', { name: 'Quét QR thanh toán hoặc hóa đơn' }).click();
    await page.getByRole('tab', { name: 'Hóa đơn' }).click();
    await expectText(page, /ảnh|Ảnh|thư viện|Chụp/);
  });

  test('xuất CSV tải về tệp có dữ liệu khoản chi', async ({ page }) => {
    await start(page);
    await page.getByRole('button', { name: 'Xuất báo cáo' }).click();
    const download = page.waitForEvent('download', { timeout: 20_000 });
    await page.getByRole('button', { name: /^Báo cáo CSV/ }).click();
    const file = await download;
    expect(file.suggestedFilename()).toMatch(/\.csv$/);
    const body = (await (await file.createReadStream()).toArray()).join('');
    expect(body.split('\n').length).toBeGreaterThan(10);
  });

  test('xuất PDF tải về tệp .pdf', async ({ page }) => {
    await start(page);
    await page.getByRole('button', { name: 'Xuất báo cáo' }).click();
    const download = page.waitForEvent('download', { timeout: 30_000 });
    await page.getByRole('button', { name: /^Báo cáo PDF/ }).click();
    expect((await download).suggestedFilename()).toMatch(/\.pdf$/);
  });

  test('chuông thông báo mở danh sách cần kiểm tra', async ({ page }) => {
    await start(page);
    await page.getByRole('button', { name: 'Thông báo' }).click();
    await expect(page.getByRole('checkbox', { name: 'Cần kiểm tra' })).toBeChecked();
  });
});
