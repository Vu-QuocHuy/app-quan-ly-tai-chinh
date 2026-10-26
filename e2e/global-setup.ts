import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { SUPABASE_URL, createUser } from './support/supabase';

const root = resolve(__dirname, '..');

export default async function globalSetup() {
  const health = await fetch(`${SUPABASE_URL}/auth/v1/health`).catch(() => null);
  if (!health) {
    throw new Error('Local Supabase is not running. Run `npx supabase start` first.');
  }
  if (!existsSync(resolve(root, 'build/web-e2e/index.html'))) {
    throw new Error('Missing build/web-e2e. Run `npm run e2e:build` first.');
  }
  // Fresh demo dataset every run so read-only assertions stay deterministic.
  execFileSync('node', ['e2e/seed/demo-account.mjs'], { cwd: root, stdio: 'inherit' });

  // Empty accounts for flows that mutate data (CRUD, groups, sharing).
  const stamp = Date.now();
  const users = {
    owner: await createUser(`owner-${stamp}@e2e.test`, 'Chủ Nhóm'),
    member: await createUser(`member-${stamp}@e2e.test`, 'Thành Viên'),
    fresh: await createUser(`fresh-${stamp}@e2e.test`, ''),
  };
  mkdirSync(resolve(__dirname, '.auth'), { recursive: true });
  writeFileSync(resolve(__dirname, '.auth/users.json'), JSON.stringify(users, null, 2));
}
