alter function public.apply_invoice_sync(text, jsonb, integer)
  security definer;
alter function public.apply_invoice_sync(text, jsonb, integer)
  set search_path = public, pg_temp;
alter function public.apply_reference_sync(text, text, text, jsonb)
  set search_path = public, pg_temp;
alter function public.pull_invoice_changes(timestamptz, text, integer)
  set search_path = public, pg_temp;
alter function public.pull_reference_changes(text, timestamptz, text, integer)
  set search_path = public, pg_temp;

revoke insert, update, delete on table public.profiles from anon, authenticated;
revoke insert, update, delete on table public.invoices from anon, authenticated;
revoke insert, update, delete on table public.invoice_lines from anon, authenticated;
revoke insert, update, delete on table public.field_evidences from anon, authenticated;
revoke insert, update, delete on table public.categories from anon, authenticated;
revoke insert, update, delete on table public.budgets from anon, authenticated;
revoke insert, update, delete on table public.merchant_rules from anon, authenticated;

alter table public.invoices
  add constraint invoices_id_length_check
    check (char_length(id) between 1 and 128) not valid,
  add constraint invoices_seller_name_length_check
    check (char_length(trim(seller_name)) between 1 and 500) not valid,
  add constraint invoices_amounts_check
    check (
      subtotal_minor >= 0
      and tax_minor >= 0
      and total_minor >= 0
    ) not valid,
  add constraint invoices_text_limits_check
    check (
      (seller_tax_code is null or char_length(seller_tax_code) <= 64)
      and (invoice_number is null or char_length(invoice_number) <= 128)
      and (invoice_symbol is null or char_length(invoice_symbol) <= 128)
      and (notes is null or char_length(notes) <= 5000)
      and char_length(currency_code) between 3 and 12
      and char_length(source_type) between 1 and 32
      and char_length(status) between 1 and 32
    ) not valid,
  add constraint invoices_tags_limit_check
    check (cardinality(tags) <= 100) not valid;

alter table public.invoice_lines
  add constraint invoice_lines_id_length_check
    check (char_length(id) between 1 and 128) not valid,
  add constraint invoice_lines_description_length_check
    check (char_length(trim(description)) between 1 and 500) not valid,
  add constraint invoice_lines_values_check
    check (
      (quantity is null or quantity >= 0)
      and (unit_price_minor is null or unit_price_minor >= 0)
      and (tax_rate is null or tax_rate between 0 and 100)
      and total_minor >= 0
    ) not valid;

alter table public.field_evidences
  add constraint field_evidences_id_length_check
    check (char_length(id) between 1 and 128) not valid,
  add constraint field_evidences_text_limits_check
    check (
      char_length(trim(field_name)) between 1 and 64
      and char_length(normalized_value) <= 5000
      and (raw_value is null or char_length(raw_value) <= 5000)
      and char_length(source_type) between 1 and 32
    ) not valid;

alter table public.categories
  add constraint categories_id_length_check
    check (char_length(id) between 1 and 128) not valid,
  add constraint categories_text_limits_check
    check (
      char_length(trim(name)) between 1 and 80
      and char_length(icon_name) between 1 and 64
    ) not valid;

alter table public.budgets
  add constraint budgets_id_length_check
    check (char_length(id) between 1 and 128) not valid,
  add constraint budgets_limit_check
    check (limit_minor >= 0) not valid;

alter table public.merchant_rules
  add constraint merchant_rules_id_length_check
    check (char_length(id) between 1 and 128) not valid,
  add constraint merchant_rules_text_limits_check
    check (
      char_length(trim(normalized_merchant)) between 1 and 300
      and char_length(category_id) between 1 and 128
    ) not valid;
