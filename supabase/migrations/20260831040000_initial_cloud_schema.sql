-- HoaDon Insight cloud schema.
-- The Flutter app remains local-first; this schema stores each authenticated
-- user's synchronized data and never trusts a user_id supplied by the client.

create extension if not exists pgcrypto;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invoices (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  cloud_id uuid not null default gen_random_uuid(),
  seller_name text not null,
  seller_tax_code text,
  invoice_number text,
  invoice_symbol text,
  issued_at timestamptz,
  currency_code text not null default 'VND',
  subtotal_minor bigint not null default 0,
  tax_minor bigint not null default 0,
  total_minor bigint not null default 0,
  source_type text not null,
  source_hash text,
  status text not null,
  category_id text,
  notes text,
  tags text[] not null default '{}',
  revision integer not null default 1 check (revision > 0),
  confirmed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (cloud_id)
);

create table public.invoice_lines (
  user_id uuid not null,
  id text not null,
  invoice_id text not null,
  description text not null,
  quantity numeric,
  unit_price_minor bigint,
  tax_rate numeric,
  total_minor bigint not null default 0,
  category_id text,
  primary key (user_id, id),
  foreign key (user_id, invoice_id)
    references public.invoices(user_id, id) on delete cascade
);

create table public.field_evidences (
  user_id uuid not null,
  id text not null,
  invoice_id text not null,
  field_name text not null,
  raw_value text,
  normalized_value text not null,
  source_type text not null,
  confidence double precision not null check (confidence between 0 and 1),
  corrected_by_user boolean not null default false,
  primary key (user_id, id),
  foreign key (user_id, invoice_id)
    references public.invoices(user_id, id) on delete cascade
);

create table public.categories (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  name text not null,
  icon_name text not null,
  color_value bigint not null,
  is_system boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.budgets (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  month_key text not null check (month_key ~ '^\\d{4}-(0[1-9]|1[0-2])$'),
  category_id text not null,
  limit_minor bigint not null check (limit_minor >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (user_id, month_key, category_id),
  foreign key (user_id, category_id)
    references public.categories(user_id, id) on delete cascade
);

create table public.merchant_rules (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null,
  normalized_merchant text not null,
  category_id text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (user_id, normalized_merchant),
  foreign key (user_id, category_id)
    references public.categories(user_id, id) on delete cascade
);

create index invoices_user_updated_idx
  on public.invoices (user_id, updated_at desc, id desc);
create index invoices_user_issued_idx
  on public.invoices (user_id, issued_at desc)
  where deleted_at is null;
create index invoices_user_category_idx
  on public.invoices (user_id, category_id)
  where deleted_at is null;
create unique index invoices_user_source_hash_idx
  on public.invoices (user_id, source_hash)
  where source_hash is not null and deleted_at is null;
create index invoice_lines_invoice_idx
  on public.invoice_lines (user_id, invoice_id);
create index field_evidences_invoice_idx
  on public.field_evidences (user_id, invoice_id);
create index budgets_user_month_idx
  on public.budgets (user_id, month_key);

alter table public.profiles enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.field_evidences enable row level security;
alter table public.categories enable row level security;
alter table public.budgets enable row level security;
alter table public.merchant_rules enable row level security;

revoke all on table public.profiles from anon;
revoke all on table public.invoices from anon;
revoke all on table public.invoice_lines from anon;
revoke all on table public.field_evidences from anon;
revoke all on table public.categories from anon;
revoke all on table public.budgets from anon;
revoke all on table public.merchant_rules from anon;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.invoices to authenticated;
grant select, insert, update, delete on table public.invoice_lines to authenticated;
grant select, insert, update, delete on table public.field_evidences to authenticated;
grant select, insert, update, delete on table public.categories to authenticated;
grant select, insert, update, delete on table public.budgets to authenticated;
grant select, insert, update, delete on table public.merchant_rules to authenticated;

create policy profiles_owner_all on public.profiles
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy invoices_owner_all on public.invoices
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy invoice_lines_owner_all on public.invoice_lines
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy field_evidences_owner_all on public.field_evidences
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy categories_owner_all on public.categories
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy budgets_owner_all on public.budgets
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy merchant_rules_owner_all on public.merchant_rules
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Atomically applies one local outbox event. Incoming stale revisions are
-- ignored, preventing an older device from overwriting a newer cloud record.
create or replace function public.apply_invoice_sync(
  p_operation text,
  p_payload jsonb,
  p_revision integer
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_invoice_id text := nullif(p_payload ->> 'id', '');
  v_line jsonb;
  v_evidence jsonb;
  v_rows integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if v_invoice_id is null then
    raise exception 'Invoice id is required' using errcode = '22023';
  end if;
  if p_revision is null or p_revision < 1 then
    raise exception 'Revision must be positive' using errcode = '22023';
  end if;

  if p_operation = 'delete' then
    update public.invoices
    set deleted_at = coalesce(
          nullif(p_payload ->> 'deletedAt', '')::timestamptz,
          now()
        ),
        updated_at = now(),
        revision = p_revision
    where user_id = v_user_id
      and id = v_invoice_id
      and revision <= p_revision;
    return;
  end if;

  if p_operation <> 'upsert' then
    raise exception 'Unsupported operation: %', p_operation
      using errcode = '22023';
  end if;

  insert into public.invoices (
    user_id,
    id,
    seller_name,
    seller_tax_code,
    invoice_number,
    invoice_symbol,
    issued_at,
    currency_code,
    subtotal_minor,
    tax_minor,
    total_minor,
    source_type,
    source_hash,
    status,
    category_id,
    notes,
    tags,
    revision,
    confirmed_at,
    deleted_at,
    created_at,
    updated_at
  ) values (
    v_user_id,
    v_invoice_id,
    coalesce(p_payload ->> 'sellerName', ''),
    nullif(p_payload ->> 'sellerTaxCode', ''),
    nullif(p_payload ->> 'invoiceNumber', ''),
    nullif(p_payload ->> 'invoiceSymbol', ''),
    nullif(p_payload ->> 'issuedAt', '')::timestamptz,
    coalesce(nullif(p_payload ->> 'currencyCode', ''), 'VND'),
    coalesce((p_payload ->> 'subtotalMinor')::bigint, 0),
    coalesce((p_payload ->> 'taxMinor')::bigint, 0),
    coalesce((p_payload ->> 'totalMinor')::bigint, 0),
    coalesce(p_payload ->> 'sourceType', 'unknown'),
    nullif(p_payload ->> 'sourceHash', ''),
    coalesce(p_payload ->> 'status', 'draft'),
    nullif(p_payload ->> 'categoryId', ''),
    nullif(p_payload ->> 'notes', ''),
    array(
      select jsonb_array_elements_text(coalesce(p_payload -> 'tags', '[]'::jsonb))
    ),
    p_revision,
    nullif(p_payload ->> 'confirmedAt', '')::timestamptz,
    nullif(p_payload ->> 'deletedAt', '')::timestamptz,
    coalesce(
      nullif(p_payload ->> 'createdAt', '')::timestamptz,
      now()
    ),
    coalesce(
      nullif(p_payload ->> 'updatedAt', '')::timestamptz,
      now()
    )
  )
  on conflict (user_id, id) do update set
    seller_name = excluded.seller_name,
    seller_tax_code = excluded.seller_tax_code,
    invoice_number = excluded.invoice_number,
    invoice_symbol = excluded.invoice_symbol,
    issued_at = excluded.issued_at,
    currency_code = excluded.currency_code,
    subtotal_minor = excluded.subtotal_minor,
    tax_minor = excluded.tax_minor,
    total_minor = excluded.total_minor,
    source_type = excluded.source_type,
    source_hash = excluded.source_hash,
    status = excluded.status,
    category_id = excluded.category_id,
    notes = excluded.notes,
    tags = excluded.tags,
    revision = excluded.revision,
    confirmed_at = excluded.confirmed_at,
    deleted_at = excluded.deleted_at,
    updated_at = excluded.updated_at
  where public.invoices.revision <= excluded.revision;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return;
  end if;

  delete from public.invoice_lines
  where user_id = v_user_id and invoice_id = v_invoice_id;

  for v_line in
    select value
    from jsonb_array_elements(coalesce(p_payload -> 'lines', '[]'::jsonb))
  loop
    insert into public.invoice_lines (
      user_id,
      id,
      invoice_id,
      description,
      quantity,
      unit_price_minor,
      tax_rate,
      total_minor,
      category_id
    ) values (
      v_user_id,
      v_line ->> 'id',
      v_invoice_id,
      coalesce(v_line ->> 'description', ''),
      nullif(v_line ->> 'quantity', '')::numeric,
      nullif(v_line ->> 'unitPriceMinor', '')::bigint,
      nullif(v_line ->> 'taxRate', '')::numeric,
      coalesce((v_line ->> 'totalMinor')::bigint, 0),
      nullif(v_line ->> 'categoryId', '')
    );
  end loop;

  if p_payload ? 'evidence' then
    delete from public.field_evidences
    where user_id = v_user_id and invoice_id = v_invoice_id;

    for v_evidence in
      select value
      from jsonb_array_elements(coalesce(p_payload -> 'evidence', '[]'::jsonb))
    loop
      insert into public.field_evidences (
        user_id,
        id,
        invoice_id,
        field_name,
        raw_value,
        normalized_value,
        source_type,
        confidence,
        corrected_by_user
      ) values (
        v_user_id,
        v_evidence ->> 'id',
        v_invoice_id,
        coalesce(v_evidence ->> 'fieldName', ''),
        v_evidence ->> 'rawValue',
        coalesce(v_evidence ->> 'normalizedValue', ''),
        coalesce(v_evidence ->> 'sourceType', 'unknown'),
        coalesce((v_evidence ->> 'confidence')::double precision, 0),
        coalesce((v_evidence ->> 'correctedByUser')::boolean, false)
      );
    end loop;
  end if;
end;
$$;

revoke all on function public.apply_invoice_sync(text, jsonb, integer)
  from public, anon;
grant execute on function public.apply_invoice_sync(text, jsonb, integer)
  to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'receipt-images',
  'receipt-images',
  false,
  15728640,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy receipt_images_owner_select
  on storage.objects for select to authenticated
  using (
    bucket_id = 'receipt-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy receipt_images_owner_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'receipt-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy receipt_images_owner_update
  on storage.objects for update to authenticated
  using (
    bucket_id = 'receipt-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'receipt-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy receipt_images_owner_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'receipt-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
