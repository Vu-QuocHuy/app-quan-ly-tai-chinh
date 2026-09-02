-- Reference data sync for categories, budgets and merchant rules.
-- These records use the same local-first outbox as invoices.

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

  insert into public.categories (
    user_id,
    id,
    name,
    icon_name,
    color_value,
    is_system
  )
  select
    new.id,
    defaults.id,
    defaults.name,
    defaults.icon_name,
    defaults.color_value,
    true
  from (
    values
      ('food', 'Ăn uống', 'restaurant', 4293548044::bigint),
      ('transport', 'Di chuyển', 'directions_car', 4280640491::bigint),
      ('shopping', 'Mua sắm', 'shopping_bag', 4286331629::bigint),
      ('utilities', 'Tiện ích', 'bolt', 4291463684::bigint),
      ('health', 'Y tế', 'health_and_safety', 4292617766::bigint),
      ('education', 'Giáo dục', 'school', 4278751666::bigint),
      ('entertainment', 'Giải trí', 'movie', 4292552567::bigint),
      ('other', 'Khác', 'category', 4284773515::bigint)
  ) as defaults(id, name, icon_name, color_value)
  on conflict (user_id, id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Backfill defaults for users created before this migration.
insert into public.categories (
  user_id,
  id,
  name,
  icon_name,
  color_value,
  is_system
)
select
  users.id,
  defaults.id,
  defaults.name,
  defaults.icon_name,
  defaults.color_value,
  true
from auth.users as users
cross join (
  values
    ('food', 'Ăn uống', 'restaurant', 4293548044::bigint),
    ('transport', 'Di chuyển', 'directions_car', 4280640491::bigint),
    ('shopping', 'Mua sắm', 'shopping_bag', 4286331629::bigint),
    ('utilities', 'Tiện ích', 'bolt', 4291463684::bigint),
    ('health', 'Y tế', 'health_and_safety', 4292617766::bigint),
    ('education', 'Giáo dục', 'school', 4278751666::bigint),
    ('entertainment', 'Giải trí', 'movie', 4292552567::bigint),
    ('other', 'Khác', 'category', 4284773515::bigint)
) as defaults(id, name, icon_name, color_value)
on conflict (user_id, id) do nothing;

create or replace function public.apply_reference_sync(
  p_aggregate_type text,
  p_operation text,
  p_payload jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id text := nullif(p_payload ->> 'id', '');
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if v_id is null then
    raise exception 'Reference id is required' using errcode = '22023';
  end if;
  if p_operation not in ('upsert', 'delete') then
    raise exception 'Unsupported operation: %', p_operation
      using errcode = '22023';
  end if;

  if p_aggregate_type = 'category' then
    if p_operation = 'delete' then
      delete from public.categories
      where user_id = v_user_id and id = v_id and is_system = false;
      return;
    end if;

    insert into public.categories (
      user_id, id, name, icon_name, color_value, is_system, updated_at
    ) values (
      v_user_id,
      v_id,
      coalesce(p_payload ->> 'name', ''),
      coalesce(p_payload ->> 'iconName', 'category'),
      coalesce((p_payload ->> 'colorValue')::bigint, 0),
      coalesce((p_payload ->> 'isSystem')::boolean, false),
      now()
    )
    on conflict (user_id, id) do update set
      name = excluded.name,
      icon_name = excluded.icon_name,
      color_value = excluded.color_value,
      is_system = excluded.is_system,
      updated_at = now();
    return;
  end if;

  if p_aggregate_type = 'budget' then
    if p_operation = 'delete' then
      delete from public.budgets
      where user_id = v_user_id and id = v_id;
      return;
    end if;

    insert into public.budgets (
      user_id, id, month_key, category_id, limit_minor, updated_at
    ) values (
      v_user_id,
      v_id,
      p_payload ->> 'monthKey',
      p_payload ->> 'categoryId',
      coalesce((p_payload ->> 'limitMinor')::bigint, 0),
      now()
    )
    on conflict (user_id, id) do update set
      month_key = excluded.month_key,
      category_id = excluded.category_id,
      limit_minor = excluded.limit_minor,
      updated_at = now();
    return;
  end if;

  if p_aggregate_type = 'merchant_rule' then
    if p_operation = 'delete' then
      delete from public.merchant_rules
      where user_id = v_user_id and id = v_id;
      return;
    end if;

    insert into public.merchant_rules (
      user_id, id, normalized_merchant, category_id, updated_at
    ) values (
      v_user_id,
      v_id,
      coalesce(p_payload ->> 'normalizedMerchant', v_id),
      p_payload ->> 'categoryId',
      now()
    )
    on conflict (user_id, id) do update set
      normalized_merchant = excluded.normalized_merchant,
      category_id = excluded.category_id,
      updated_at = now();
    return;
  end if;

  raise exception 'Unsupported aggregate type: %', p_aggregate_type
    using errcode = '22023';
end;
$$;

revoke all on function public.apply_reference_sync(text, text, jsonb)
  from public, anon;
grant execute on function public.apply_reference_sync(text, text, jsonb)
  to authenticated;
