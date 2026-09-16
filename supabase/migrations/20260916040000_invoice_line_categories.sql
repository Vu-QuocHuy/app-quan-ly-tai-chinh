alter table public.invoice_lines
  add column if not exists category_id text;

comment on column public.invoice_lines.category_id is
  'User-confirmed spending category for this invoice line.';
