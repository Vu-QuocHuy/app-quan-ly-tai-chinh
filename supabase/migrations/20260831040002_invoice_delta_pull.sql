-- Returns the authenticated user's invoice changes in a stable cursor order.
-- Deleted invoices remain visible as tombstones until retention is introduced.
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
set search_path = ''
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
      or (
        i.updated_at = p_since
        and i.id > coalesce(p_after_id, '')
      )
    )
  order by i.updated_at asc, i.id asc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

revoke all on function public.pull_invoice_changes(timestamptz, text, integer)
  from public, anon;
grant execute on function public.pull_invoice_changes(timestamptz, text, integer)
  to authenticated;
