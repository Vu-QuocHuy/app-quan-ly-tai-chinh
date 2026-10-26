// Seeds a demo account with ~12 months of varied income and expenses on a
// LOCAL Supabase stack (`npx supabase start`). Data goes through the same
// sync RPCs the app uses, so the app pulls it down after login.
//
// Usage: node e2e/seed/demo-account.mjs
// Env:   SUPABASE_URL (default http://127.0.0.1:54321)
//        SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY (default: local demo keys)
//        DEMO_EMAIL, DEMO_PASSWORD
// Credentials are written to config/demo-account.local.json (gitignored).

import { randomUUID, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const URL_ = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(URL_)) {
  throw new Error(`Refusing to seed non-local Supabase: ${URL_}`);
}
// Public demo keys printed by `supabase status` for every local stack.
const ANON =
  process.env.SUPABASE_ANON_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const SERVICE =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
const EMAIL = process.env.DEMO_EMAIL ?? 'demo@finmi.test';
const PASSWORD = process.env.DEMO_PASSWORD ?? `Demo-${randomBytes(6).toString('hex')}`;

// Deterministic RNG so every reseed produces the same dataset.
let seed = 20261023;
const rand = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32);
const between = (min, max) => min + Math.floor(rand() * (max - min + 1));
const pick = (list) => list[Math.floor(rand() * list.length)];
const round = (amount, step = 1000) => Math.max(step, Math.round(amount / step) * step);

async function http(path, { method = 'POST', key = ANON, token, body } = {}) {
  const res = await fetch(`${URL_}${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${token ?? key}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

async function ensureUser() {
  const list = await http('/auth/v1/admin/users?per_page=1000', { method: 'GET', key: SERVICE });
  const existing = list.users.find((u) => u.email === EMAIL);
  if (existing) {
    // Reuse the user and wipe its rows. Deleting the auth user would be simpler
    // but fails while group_expense_splits is in supabase_realtime without a
    // replica identity (see e2e/REPORT.md).
    await http(`/auth/v1/admin/users/${existing.id}`, {
      method: 'PUT', key: SERVICE, body: { password: PASSWORD },
    });
    // service_role has no table grants (hardening migrations), so wipe via psql.
    const db = execFileSync('docker', ['ps', '--format', '{{.Names}}'], { encoding: 'utf8' })
      .split('\n').find((name) => name.startsWith('supabase_db_'));
    const tables = ['invoices', 'income_entries', 'planning_entries', 'budgets', 'merchant_rules', 'categories'];
    execFileSync('docker', ['exec', '-i', db, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qc',
      tables.map((t) => `delete from public.${t} where user_id = '${existing.id}';`).join(' ')]);
  } else {
    await http('/auth/v1/admin/users', {
      key: SERVICE,
      body: { email: EMAIL, password: PASSWORD, email_confirm: true },
    });
  }
  const session = await http('/auth/v1/token?grant_type=password', {
    body: { email: EMAIL, password: PASSWORD },
  });
  return { userId: session.user.id, token: session.access_token };
}

// ---- Reference data ------------------------------------------------------

const expenseCategories = [
  // App system defaults (lib/core/database/app_database.dart) — needed server
  // side because budgets reference categories by FK.
  ['food', 'Ăn uống', 'restaurant', 0xffea580c, true],
  ['transport', 'Di chuyển', 'directions_car', 0xff2563eb, true],
  ['shopping', 'Mua sắm', 'shopping_bag', 0xff7c3aed, true],
  ['utilities', 'Tiện ích', 'bolt', 0xffca8a04, true],
  ['health', 'Y tế', 'health_and_safety', 0xffdc2626, true],
  ['education', 'Giáo dục', 'school', 0xff0891b2, true],
  ['entertainment', 'Giải trí', 'movie', 0xffdb2777, true],
  ['other', 'Khác', 'category', 0xff64748b, true],
  // Custom categories a real user would add.
  ['demo_housing', 'Nhà ở', 'home', 0xff0f766e, false],
  ['demo_travel', 'Du lịch', 'flight', 0xff0284c7, false],
  ['demo_pets', 'Thú cưng', 'pets', 0xffa16207, false],
  ['demo_fitness', 'Thể thao', 'fitness_center', 0xff16a34a, false],
  ['demo_family', 'Gia đình & hiếu hỉ', 'category', 0xffbe185d, false],
].map(([id, name, iconName, colorValue, isSystem]) => ({
  id, name, iconName, colorValue, isSystem, kind: 'expense',
}));

const incomeCategories = [
  ['income_uncategorized', 'Chưa phân loại', 'category', 0xff64748b, true],
  ['demo_income_salary', 'Lương', 'category', 0xff15803d, false],
  ['demo_income_bonus', 'Thưởng', 'category', 0xffca8a04, false],
  ['demo_income_freelance', 'Freelance', 'category', 0xff2563eb, false],
  ['demo_income_invest', 'Đầu tư & lãi tiết kiệm', 'category', 0xff7c3aed, false],
  ['demo_income_rent', 'Cho thuê', 'home', 0xff0f766e, false],
  ['demo_income_gift', 'Được tặng', 'category', 0xffdb2777, false],
  ['demo_income_sell', 'Bán đồ cũ', 'shopping_bag', 0xffea580c, false],
].map(([id, name, iconName, colorValue, isSystem]) => ({
  id, name, iconName, colorValue, isSystem, kind: 'income',
}));

const monthlyBudgets = {
  food: 6_000_000,
  transport: 1_500_000,
  shopping: 3_000_000,
  utilities: 2_000_000,
  entertainment: 1_500_000,
  demo_housing: 7_000_000,
  health: 1_000_000,
};

// ---- Expense templates -----------------------------------------------------
// [seller, category, min, max, lines?]

const daily = [
  ['Highlands Coffee', 'food', 45_000, 95_000, ['Phin sữa đá', 'Trà sen vàng', 'Bánh mì que']],
  ['Phúc Long', 'food', 50_000, 120_000, ['Trà sữa Phúc Long', 'Trà đào', 'Bánh croissant']],
  ['Cơm tấm Ba Ghiền', 'food', 55_000, 90_000, ['Cơm sườn bì chả', 'Canh khổ qua']],
  ['Phở Thìn', 'food', 60_000, 85_000, ['Phở bò tái lăn', 'Quẩy']],
  ['Bún chả Hương Liên', 'food', 50_000, 110_000, ['Bún chả', 'Nem cua bể']],
  ['Bánh mì Huynh Hoa', 'food', 35_000, 75_000, ['Bánh mì thập cẩm']],
  ['Circle K', 'food', 20_000, 85_000, ['Nước suối', 'Mì ly', 'Snack']],
  ['GrabFood', 'food', 70_000, 220_000, ['Gà rán', 'Pizza', 'Bún bò Huế']],
  ['ShopeeFood', 'food', 60_000, 180_000, ['Cơm gà', 'Trà sữa', 'Bánh tráng trộn']],
  ['Grab', 'transport', 25_000, 140_000, ['GrabBike', 'GrabCar']],
  ['Be', 'transport', 20_000, 110_000, ['beBike', 'beCar']],
  ['Xanh SM', 'transport', 35_000, 160_000, ['Taxi điện']],
];

const weekly = [
  ['WinMart', 'food', 250_000, 900_000, ['Rau củ', 'Thịt heo', 'Trứng gà', 'Sữa tươi', 'Gạo ST25']],
  ['Co.op Mart', 'food', 300_000, 1_100_000, ['Thịt bò', 'Cá hồi', 'Trái cây', 'Nước giặt']],
  ['Bách Hóa Xanh', 'food', 150_000, 600_000, ['Rau muống', 'Cà chua', 'Đậu hũ', 'Nước mắm']],
  ['Petrolimex', 'transport', 80_000, 250_000, ['Xăng RON 95-III']],
  ['CGV Cinemas', 'entertainment', 110_000, 320_000, ['Vé xem phim 2D', 'Combo bắp nước']],
  ['Lotte Cinema', 'entertainment', 100_000, 280_000, ['Vé xem phim', 'Bắp caramel']],
  ['Quán nhậu Gánh', 'food', 300_000, 900_000, ['Lẩu thái', 'Bia Tiger', 'Mực nướng']],
  ['Shopee', 'shopping', 90_000, 750_000, ['Ốp lưng điện thoại', 'Đồ gia dụng', 'Áo thun']],
  ['Lazada', 'shopping', 120_000, 900_000, ['Tai nghe', 'Bình giữ nhiệt', 'Sách']],
  ['Tiki', 'shopping', 80_000, 500_000, ['Sách kỹ năng', 'Văn phòng phẩm']],
  ['Pharmacity', 'health', 40_000, 350_000, ['Vitamin C', 'Thuốc cảm', 'Khẩu trang']],
  ['California Fitness', 'demo_fitness', 60_000, 150_000, ['Nước điện giải', 'Khăn tập']],
];

const monthly = [
  // [seller, category, amount|[min,max], dayOfMonth, lines]
  ['Tiền thuê nhà', 'demo_housing', 6_500_000, 1, ['Tiền phòng tháng']],
  ['EVN HCMC', 'utilities', [650_000, 1_650_000], 8, ['Tiền điện sinh hoạt']],
  ['SAWACO', 'utilities', [90_000, 180_000], 9, ['Tiền nước']],
  ['FPT Telecom', 'utilities', 265_000, 5, ['Internet cáp quang 150Mbps']],
  ['Viettel', 'utilities', 150_000, 6, ['Cước di động trả sau']],
  ['Netflix', 'entertainment', 260_000, 12, ['Gói Standard']],
  ['Spotify', 'entertainment', 59_000, 15, ['Premium Individual']],
  ['California Fitness', 'demo_fitness', 900_000, 3, ['Phí hội viên tháng']],
  ['Ba mẹ', 'demo_family', 3_000_000, 10, ['Gửi tiền ba mẹ']],
  ['Pet Mart', 'demo_pets', [250_000, 700_000], 18, ['Thức ăn hạt Royal Canin', 'Cát vệ sinh']],
];

// Once-off larger expenses spread across the year.
const occasional = [
  ['2025-11-20', 'Hoa tươi 20/11', 'demo_family', 450_000, ['Bó hoa tặng cô giáo']],
  ['2025-12-24', 'Vincom Center', 'shopping', 2_850_000, ['Quà Giáng sinh', 'Áo khoác']],
  ['2025-12-31', 'Nhà hàng Gogi House', 'food', 1_650_000, ['Buffet nướng 3 người']],
  ['2026-01-15', 'Thế Giới Di Động', 'shopping', 7_990_000, ['Tai nghe AirPods Pro 2']],
  ['2026-02-10', 'Lì xì Tết', 'demo_family', 5_000_000, ['Lì xì gia đình']],
  ['2026-02-12', 'Vietnam Airlines', 'demo_travel', 4_380_000, ['Vé khứ hồi HCM - Hà Nội']],
  ['2026-02-14', 'Co.op Mart', 'food', 2_400_000, ['Đồ cúng Tết', 'Bánh mứt', 'Bia lon']],
  ['2026-03-08', 'PNJ', 'shopping', 3_200_000, ['Bông tai bạc 8/3']],
  ['2026-03-22', 'Bệnh viện FV', 'health', 1_850_000, ['Khám tổng quát', 'Xét nghiệm máu']],
  ['2026-04-05', 'Bảo Việt', 'health', 6_200_000, ['Bảo hiểm sức khỏe năm']],
  ['2026-04-30', 'Agoda', 'demo_travel', 3_600_000, ['Khách sạn Vũng Tàu 2 đêm']],
  ['2026-05-02', 'Hải sản Gành Hào', 'demo_travel', 1_450_000, ['Hải sản nướng', 'Lẩu cá']],
  ['2026-05-19', 'Udemy', 'education', 349_000, ['Khóa học Flutter nâng cao']],
  ['2026-06-01', 'Fahasa', 'education', 680_000, ['Sách IELTS', 'Sách lập trình']],
  ['2026-06-15', 'IDP Việt Nam', 'education', 4_664_000, ['Lệ phí thi IELTS']],
  ['2026-06-28', 'Điện Máy Xanh', 'shopping', 12_490_000, ['Máy lọc không khí', 'Nồi chiên không dầu']],
  ['2026-07-10', 'Vietjet Air', 'demo_travel', 5_120_000, ['Vé khứ hồi HCM - Đà Nẵng']],
  ['2026-07-11', 'Mường Thanh Đà Nẵng', 'demo_travel', 4_200_000, ['Khách sạn 3 đêm']],
  ['2026-07-13', 'Bà Nà Hills', 'demo_travel', 1_800_000, ['Vé cáp treo 2 người']],
  ['2026-08-08', 'Đám cưới bạn thân', 'demo_family', 1_000_000, ['Mừng cưới']],
  ['2026-08-20', 'Garage Hùng', 'transport', 1_350_000, ['Bảo dưỡng xe máy', 'Thay nhớt', 'Thay lốp']],
  ['2026-09-05', 'Nha khoa Kim', 'health', 2_500_000, ['Cạo vôi răng', 'Trám răng']],
  ['2026-09-15', 'Thú y Pet Pro', 'demo_pets', 950_000, ['Tiêm phòng dại', 'Tẩy giun']],
  ['2026-09-30', 'Uniqlo', 'shopping', 1_890_000, ['Áo sơ mi', 'Quần kaki']],
  ['2026-10-10', 'Shopee 10.10', 'shopping', 2_350_000, ['Bàn phím cơ', 'Chuột không dây']],
  ['2026-10-20', 'Hoa tươi 20/10', 'demo_family', 600_000, ['Hoa và bánh tặng mẹ']],
];

// ---- Builders ---------------------------------------------------------------

const START = new Date(Date.UTC(2025, 10, 1)); // 2025-11-01
const END = new Date(Date.UTC(2026, 9, 23)); // 2026-10-23 (today)
const iso = (d) => d.toISOString();
// Local Vietnam time (UTC+7) at given hour.
const at = (y, m, d, hour = 12, min = 0) => new Date(Date.UTC(y, m, d, hour - 7, min));

function splitLines(total, names) {
  const count = Math.min(names.length, between(1, Math.min(3, names.length)));
  const chosen = [...names].sort(() => rand() - 0.5).slice(0, count);
  const lines = [];
  let remaining = total;
  chosen.forEach((description, index) => {
    const last = index === chosen.length - 1;
    const part = last ? remaining : round(remaining * (0.3 + rand() * 0.4));
    remaining -= part;
    lines.push({ description, totalMinor: part });
  });
  return lines.filter((l) => l.totalMinor > 0);
}

let invoiceSeq = 0;
function invoice(date, seller, categoryId, total, lineNames, extra = {}) {
  const id = randomUUID();
  const lines = splitLines(total, lineNames).map((line) => ({
    id: randomUUID(),
    description: line.description,
    quantity: 1,
    unitPriceMinor: line.totalMinor,
    totalMinor: line.totalMinor,
    categoryId,
  }));
  invoiceSeq += 1;
  const created = iso(date);
  return {
    id,
    sellerName: seller,
    invoiceSymbol: null,
    issuedAt: created,
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    discountMinor: 0,
    totalMinor: total,
    sourceType: extra.sourceType ?? (invoiceSeq % 4 === 0 ? 'imageOcr' : 'manual'),
    sourceHash: null,
    status: extra.status ?? 'confirmed',
    categoryId,
    notes: extra.notes ?? null,
    tags: extra.tags ?? [],
    createdAt: created,
    updatedAt: created,
    confirmedAt: (extra.status ?? 'confirmed') === 'confirmed' ? created : null,
    revision: 1,
    deletedAt: null,
    lines,
    evidence: [],
  };
}

function buildData() {
  const invoices = [];
  const incomes = [];
  const budgets = [];

  for (let day = new Date(START); day <= END; day = new Date(day.getTime() + 86_400_000)) {
    const y = day.getUTCFullYear();
    const m = day.getUTCMonth();
    const d = day.getUTCDate();
    const weekday = day.getUTCDay();

    // 1-3 small daily spends.
    for (let i = 0, n = between(1, 3); i < n; i++) {
      const [seller, cat, min, max, lines] = pick(daily);
      invoices.push(invoice(at(y, m, d, between(7, 21), between(0, 59)), seller, cat, round(between(min, max)), lines));
    }
    // Weekend / weekly spends.
    if (weekday === 0 || weekday === 6 || rand() < 0.15) {
      const [seller, cat, min, max, lines] = pick(weekly);
      invoices.push(invoice(at(y, m, d, between(9, 20)), seller, cat, round(between(min, max), 5000), lines));
    }
    // Monthly bills.
    for (const [seller, cat, amount, dom, lines] of monthly) {
      if (d !== dom) continue;
      const total = Array.isArray(amount) ? round(between(...amount), 1000) : amount;
      invoices.push(invoice(at(y, m, d, 9), seller, cat, total, lines, { tags: ['định kỳ'] }));
    }

    // Income.
    const monthKey = `${y}-${String(m + 1).padStart(2, '0')}`;
    if (d === 5) {
      incomes.push(income(at(y, m, d, 9), 22_000_000, 'fixed', 'demo_income_salary', `Lương tháng ${m === 0 ? 12 : m}`));
    }
    if (d === 25) {
      incomes.push(income(at(y, m, d, 10), 3_500_000, 'fixed', 'demo_income_rent', 'Tiền cho thuê phòng trọ'));
    }
    if (d === 28) {
      incomes.push(income(at(y, m, d, 8), round(between(120_000, 260_000)), 'fixed', 'demo_income_invest', 'Lãi tiết kiệm ngân hàng'));
    }
    if (d === 15 && rand() < 0.7) {
      incomes.push(income(at(y, m, d, 20), round(between(2_000_000, 9_000_000), 100_000), 'manual', 'demo_income_freelance', pick(['Dự án landing page', 'Thiết kế logo', 'App Flutter cho khách', 'Dịch tài liệu'])));
    }
    if (d === 1) {
      for (const [categoryId, limitMinor] of Object.entries(monthlyBudgets)) {
        budgets.push({ id: `demo_budget_${monthKey}_${categoryId}`, monthKey, categoryId, limitMinor });
      }
    }
  }

  // Bonuses and odd income.
  incomes.push(income(at(2026, 0, 20, 9), 30_000_000, 'manual', 'demo_income_bonus', 'Thưởng Tết'));
  incomes.push(income(at(2026, 1, 11, 18), 4_000_000, 'manual', 'demo_income_gift', 'Lì xì Tết'));
  incomes.push(income(at(2026, 5, 30, 9), 8_000_000, 'manual', 'demo_income_bonus', 'Thưởng KPI quý 2'));
  incomes.push(income(at(2026, 3, 18, 15), 2_500_000, 'manual', 'demo_income_sell', 'Bán điện thoại cũ'));
  incomes.push(income(at(2026, 8, 2, 11), 1_200_000, 'unclassified', 'income_uncategorized', 'Bạn trả tiền ăn'));
  incomes.push(income(at(2026, 9, 3, 16), 5_000_000, 'manual', 'demo_income_invest', 'Lãi chứng khoán'));

  for (const [date, seller, cat, total, lines] of occasional) {
    const [y, m, d] = date.split('-').map(Number);
    invoices.push(invoice(at(y, m - 1, d, 14), seller, cat, total, lines, { sourceType: 'imageOcr' }));
  }
  // A couple of drafts awaiting review and an untagged "other" expense.
  invoices.push(invoice(at(2026, 9, 22, 19), 'Lotteria', 'food', 135_000, ['Combo gà rán'], { status: 'needsReview', sourceType: 'imageOcr' }));
  invoices.push(invoice(at(2026, 9, 21, 12), 'Cửa hàng tạp hóa', 'other', 58_000, ['Đồ dùng lặt vặt'], { status: 'needsReview' }));
  invoices.push(invoice(at(2026, 6, 4, 10), 'Phí chuyển khoản', 'other', 11_000, ['Phí SMS Banking'], { notes: 'Phí ngân hàng' }));

  return { invoices, incomes, budgets };
}

function income(date, amountMinor, source, categoryId, note) {
  return {
    id: randomUUID(),
    amountMinor,
    source,
    categoryId,
    note,
    receivedAt: iso(date),
    updatedAt: iso(date),
  };
}

// ---- Push ------------------------------------------------------------------

async function rpc(token, fn, params) {
  return http(`/rest/v1/rpc/${fn}`, { token, body: params });
}

async function inBatches(items, size, fn) {
  for (let i = 0; i < items.length; i += size) {
    await Promise.all(items.slice(i, i + size).map(fn));
  }
}

async function main() {
  const { userId, token } = await ensureUser();
  const base = { p_expected_user_id: userId };
  await rpc(token, 'save_personal_profile', { p_display_name: 'Nguyễn Demo', p_phone: '0901234567' });

  for (const category of [...expenseCategories, ...incomeCategories]) {
    await rpc(token, 'apply_reference_sync_checked', {
      ...base, p_event_id: randomUUID(), p_aggregate_type: 'category', p_operation: 'upsert', p_payload: category,
    });
  }
  const { invoices, incomes, budgets } = buildData();
  await inBatches(budgets, 10, (b) => rpc(token, 'apply_reference_sync_checked', {
    ...base, p_event_id: randomUUID(), p_aggregate_type: 'budget', p_operation: 'upsert', p_payload: b,
  }));
  await inBatches(incomes, 10, (i) => rpc(token, 'apply_income_sync_checked', {
    ...base, p_operation: 'upsert', p_payload: i,
  }));
  await inBatches(invoices, 10, (inv) => rpc(token, 'apply_invoice_sync_checked', {
    ...base, p_operation: 'upsert', p_payload: inv, p_revision: 1,
  }));

  const out = resolve(root, 'config/demo-account.local.json');
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, JSON.stringify({ email: EMAIL, password: PASSWORD, userId }, null, 2) + '\n');

  const sum = (list, key) => list.reduce((acc, item) => acc + item[key], 0);
  console.log(JSON.stringify({
    email: EMAIL,
    credentialsFile: 'config/demo-account.local.json',
    categories: expenseCategories.length + incomeCategories.length,
    budgets: budgets.length,
    incomes: incomes.length,
    incomeTotal: sum(incomes, 'amountMinor'),
    invoices: invoices.length,
    expenseTotal: sum(invoices, 'totalMinor'),
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
