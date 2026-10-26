import { sql } from './supabase';

/** Ground truth for a user's month, computed from the cloud DB. */
export function monthTotals(userId: string, month: string) {
  const [row] = sql<{ chi: number; n: number; thu: number }>(`
    select
      (select coalesce(sum(total_minor), 0) from public.invoices
        where user_id = '${userId}' and status = 'confirmed' and deleted_at is null
          and to_char(issued_at at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') = '${month}')::bigint as chi,
      (select count(*) from public.invoices
        where user_id = '${userId}' and status = 'confirmed' and deleted_at is null
          and to_char(issued_at at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') = '${month}')::int as n,
      (select coalesce(sum(amount_minor), 0) from public.income_entries
        where user_id = '${userId}' and deleted_at is null
          and to_char(received_at at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM') = '${month}')::bigint as thu`);
  return { chi: Number(row.chi), thu: Number(row.thu), n: row.n, net: Number(row.thu) - Number(row.chi) };
}

export function yearTotals(userId: string, year: number) {
  const [row] = sql<{ chi: number; thu: number }>(`
    select
      (select coalesce(sum(total_minor), 0) from public.invoices
        where user_id = '${userId}' and status = 'confirmed' and deleted_at is null
          and extract(year from issued_at at time zone 'Asia/Ho_Chi_Minh') = ${year})::bigint as chi,
      (select coalesce(sum(amount_minor), 0) from public.income_entries
        where user_id = '${userId}' and deleted_at is null
          and extract(year from received_at at time zone 'Asia/Ho_Chi_Minh') = ${year})::bigint as thu`);
  return { chi: Number(row.chi), thu: Number(row.thu) };
}
