alter table public.invoices
  add column discount_minor bigint not null default 0,
  add constraint invoices_discount_nonnegative_check
    check (discount_minor >= 0) not valid;

create or replace function public.apply_invoice_sync(
  p_operation text,
  p_payload jsonb,
  p_revision integer
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
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
    user_id, id, seller_name, seller_tax_code, invoice_number, invoice_symbol,
    issued_at, currency_code, subtotal_minor, tax_minor, discount_minor,
    total_minor, source_type, source_hash, status, category_id, notes, tags,
    revision, confirmed_at, deleted_at, created_at, updated_at
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
    coalesce((p_payload ->> 'discountMinor')::bigint, 0),
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
    coalesce(nullif(p_payload ->> 'createdAt', '')::timestamptz, now()),
    coalesce(nullif(p_payload ->> 'updatedAt', '')::timestamptz, now())
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
    discount_minor = excluded.discount_minor,
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
      user_id, id, invoice_id, description, quantity, unit_price_minor,
      tax_rate, total_minor, category_id
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
        user_id, id, invoice_id, field_name, raw_value, normalized_value,
        source_type, confidence, corrected_by_user
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

create or replace function public.pull_invoice_changes(
  p_since timestamptz default null,
  p_after_id text default null,
  p_limit integer default 50
)
returns table (
  id text,
  updated_at timestamptz,
  revision integer,
  payload jsonb
)
language sql
security invoker
set search_path = public, pg_temp
as $$
  select
    i.id,
    i.updated_at,
    i.revision,
    jsonb_build_object(
      'id', i.id,
      'cloudId', i.cloud_id,
      'sellerName', i.seller_name,
      'sellerTaxCode', i.seller_tax_code,
      'invoiceNumber', i.invoice_number,
      'invoiceSymbol', i.invoice_symbol,
      'issuedAt', i.issued_at,
      'currencyCode', i.currency_code,
      'subtotalMinor', i.subtotal_minor,
      'taxMinor', i.tax_minor,
      'discountMinor', i.discount_minor,
      'totalMinor', i.total_minor,
      'sourceType', i.source_type,
      'sourceHash', i.source_hash,
      'status', i.status,
      'categoryId', i.category_id,
      'notes', i.notes,
      'tags', to_jsonb(i.tags),
      'revision', i.revision,
      'confirmedAt', i.confirmed_at,
      'deletedAt', i.deleted_at,
      'createdAt', i.created_at,
      'updatedAt', i.updated_at,
      'lines', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', l.id,
              'description', l.description,
              'quantity', l.quantity,
              'unitPriceMinor', l.unit_price_minor,
              'taxRate', l.tax_rate,
              'totalMinor', l.total_minor,
              'categoryId', l.category_id
            ) order by l.id
          )
          from public.invoice_lines l
          where l.user_id = i.user_id and l.invoice_id = i.id
        ),
        '[]'::jsonb
      ),
      'evidence', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', e.id,
              'fieldName', e.field_name,
              'rawValue', e.raw_value,
              'normalizedValue', e.normalized_value,
              'sourceType', e.source_type,
              'confidence', e.confidence,
              'correctedByUser', e.corrected_by_user
            ) order by e.id
          )
          from public.field_evidences e
          where e.user_id = i.user_id and e.invoice_id = i.id
        ),
        '[]'::jsonb
      )
    ) as payload
  from public.invoices i
  where i.user_id = (select auth.uid())
    and (
      p_since is null
      or i.updated_at > p_since
      or (i.updated_at = p_since and i.id > coalesce(p_after_id, ''))
    )
  order by i.updated_at asc, i.id asc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

revoke all on function public.pull_invoice_changes(timestamptz, text, integer)
  from public, anon;
grant execute on function public.pull_invoice_changes(timestamptz, text, integer)
  to authenticated;
