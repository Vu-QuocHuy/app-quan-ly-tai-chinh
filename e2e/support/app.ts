import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { expect, type Locator, type Page } from '@playwright/test';
import type { TestUser } from './supabase';

export const demo = (): TestUser => {
  const raw = JSON.parse(readFileSync(resolve(__dirname, '../../config/demo-account.local.json'), 'utf8'));
  return { email: raw.email, password: raw.password, id: raw.userId, name: 'Nguyễn Demo' };
};
export const users = (): Record<'owner' | 'member' | 'fresh', TestUser> =>
  JSON.parse(readFileSync(resolve(__dirname, '../.auth/users.json'), 'utf8'));

/** Waits until Flutter has rendered its semantics tree. */
export async function ready(page: Page) {
  await expect(page.locator('flt-semantics-host, flt-glass-pane').first()).toBeAttached({ timeout: 30_000 });
  await expect(page.getByRole('button').first()).toBeVisible({ timeout: 30_000 });
}

export async function login(page: Page, user: TestUser) {
  trackSync(page);
  await page.goto('/');
  await ready(page);
  await type(page, page.getByRole('textbox', { name: 'Email' }), user.email);
  await type(page, page.getByRole('textbox', { name: 'Mật khẩu' }), user.password);
  await page.getByRole('button', { name: 'Đăng nhập', exact: true }).last().click();
  await expect(page.getByRole('button', { name: 'Cài đặt' })).toBeVisible({ timeout: 45_000 });
}

const lastSync = new WeakMap<Page, number>();

/** Records sync RPC activity so callers can wait for it to go quiet. */
export function trackSync(page: Page) {
  if (lastSync.has(page)) return;
  lastSync.set(page, Date.now());
  page.on('request', (r) => {
    if (/\/rpc\/(pull_|apply_)/.test(r.url())) lastSync.set(page, Date.now());
  });
}

/** Waits until no pull/push RPC for 2s (networkidle never fires: realtime socket). */
export async function syncQuiet(page: Page) {
  trackSync(page);
  await expect
    .poll(() => Date.now() - (lastSync.get(page) ?? 0), { timeout: 90_000, intervals: [500] })
    .toBeGreaterThan(2_000);
}

/**
 * Opens a route with a full reload once sync is quiet. Hash-only navigation
 * is unreliable from pushed routes, and reloading mid-sync wedges the web
 * build (REPORT.md, B3).
 */
export async function open(page: Page, route: string) {
  await syncQuiet(page);
  await page.goto(`/#${route}`);
  await page.reload();
  await ready(page);
  await syncQuiet(page);
}

/** Starts the app from a saved state and waits for the startup sync. */
export async function start(page: Page, route = '/') {
  trackSync(page);
  await page.goto(`/#${route}`);
  await ready(page);
  await syncQuiet(page);
}

/** Backs out of pushed routes to the tab shell, without reloading. */
export async function home(page: Page) {
  const nav = page.getByRole('button', { name: 'Tổng quan', exact: true });
  for (let i = 0; i < 6 && !(await nav.isVisible()); i++) {
    const back = page.getByRole('button', { name: /^(Quay lại|Về Tổng quan|Đóng|Hủy|Bỏ qua)$/ }).first();
    if (await back.isVisible()) await back.click(); else await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
  }
  await nav.click();
  await expect(page.getByRole('button', { name: 'Thêm thu/chi' })).toBeVisible();
}

/** Pushes the outbox now via Tài khoản › Đồng bộ ngay. */
export async function syncNow(page: Page) {
  await home(page);
  await page.getByRole('button', { name: 'Cài đặt', exact: true }).click();
  await page.getByRole('button', { name: /^Tài khoản / }).click();
  await page.getByRole('button', { name: 'Đồng bộ ngay' }).click();
  await page.waitForTimeout(500);
  await syncQuiet(page);
}

/** A brand-new account, logged in, for flows that change data. */
export async function freshUser(page: Page, name = 'Người Test') {
  const { createUser } = await import('./supabase');
  const user = await createUser(`u-${Date.now()}-${Math.random().toString(36).slice(2, 7)}@e2e.test`, name);
  await login(page, user);
  await syncQuiet(page);
  return user;
}

/** Accessible names of all matches (Flutter puts row text in textContent). */
export const names = (loc: Locator) =>
  loc.evaluateAll((els) => els.map((e) => (e.getAttribute('aria-label') || e.textContent || '').replace(/\s*\n\s*/g, ' ').trim()));

/** Scrolls a lazy Flutter list until the locator is built, then into view. */
export async function scrollTo(page: Page, loc: Locator, maxSteps = 25) {
  for (let i = 0; i < maxSteps && (await loc.count()) === 0; i++) {
    await page.mouse.move(206, 500);
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(250);
  }
  await expect(loc.first()).toBeAttached();
}

/** Focus a Flutter text field and type into the real <input> it spawns. */
export async function type(page: Page, field: Locator, value: string) {
  await field.click();
  // Ctrl+A is unreliable in Flutter's formatted fields: delete char by char.
  const length = await page.evaluate(() => (document.activeElement as HTMLInputElement | null)?.value?.length ?? 0);
  await page.keyboard.press('End');
  for (let i = 0; i < length; i++) await page.keyboard.press('Backspace');
  await page.keyboard.type(value);
}

/** Formats minor VND like the app: 21102000 -> "21.102.000 ₫". */
export const vnd = (amount: number) =>
  `${amount < 0 ? '-' : ''}${Math.abs(amount).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')} ₫`;

/** Month key in Vietnam time, e.g. "2026-10"; offset in months. */
export const monthKey = (offset = 0) => {
  const now = new Date(Date.now() + 7 * 3600_000);
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + offset, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
};

export const DEMO_STATE = resolve(__dirname, '../.auth/demo.json');

/** Substring matcher for Flutter's merged semantics labels. */
export const text = (value: string) => new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));

/** Flutter puts text in aria-labels, so match against the aria snapshot. */
export async function expectText(page: Page, value: string | RegExp, timeout = 15_000) {
  await expect
    .poll(async () => page.locator('body').ariaSnapshot().catch(() => ''), { timeout })
    .toMatch(typeof value === 'string' ? text(value) : value);
}
