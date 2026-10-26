import { randomBytes } from 'node:crypto';

export const SUPABASE_URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
// Public demo keys every local `supabase start` prints.
const ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const SERVICE =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

export type TestUser = { email: string; password: string; id: string; name: string };

async function call(path: string, init: { method?: string; key?: string; token?: string; body?: unknown }) {
  const key = init.key ?? ANON;
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    method: init.method ?? 'POST',
    headers: { apikey: key, Authorization: `Bearer ${init.token ?? key}`, 'Content-Type': 'application/json' },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${path} -> ${res.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

export async function createUser(email: string, name: string): Promise<TestUser> {
  const password = `E2e-${randomBytes(6).toString('hex')}`;
  const user = await call('/auth/v1/admin/users', {
    key: SERVICE,
    body: { email, password, email_confirm: true },
  });
  if (name) {
    const token = await signIn(email, password);
    await call('/rest/v1/rpc/save_personal_profile', { token, body: { p_display_name: name, p_phone: '' } });
  }
  return { email, password, id: user.id, name };
}

export async function signIn(email: string, password: string): Promise<string> {
  const session = await call('/auth/v1/token?grant_type=password', { body: { email, password } });
  return session.access_token;
}

/** Service-role SQL-free read through PostgREST, for asserting server state. */
export async function adminSelect(table: string, query: string) {
  return call(`/rest/v1/${table}?${query}`, { method: 'GET', key: SERVICE });
}

/**
 * Runs SQL as postgres inside the local Supabase DB container and returns the
 * rows. service_role has no table grants here, so assertions read via psql.
 */
export function sql<T = Record<string, unknown>>(query: string): T[] {
  const { execFileSync } = require('node:child_process') as typeof import('node:child_process');
  const container = execFileSync('docker', ['ps', '--format', '{{.Names}}'], { encoding: 'utf8' })
    .split('\n')
    .find((name) => name.startsWith('supabase_db_'));
  if (!container) throw new Error('supabase_db container not running');
  const out = execFileSync(
    'docker',
    ['exec', '-i', container, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-tAc',
      `select coalesce(json_agg(_q), '[]') from (${query}) _q`],
    { encoding: 'utf8' },
  );
  return JSON.parse(out.trim());
}
