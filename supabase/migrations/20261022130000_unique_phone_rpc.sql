-- Migration: Add unique phone validation, RPCs for phone checking, and enforce unique phone numbers across profiles

-- 1. Helper function: check if a phone number is registered by any user in Finmi
create or replace function public.check_phone_registered(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text := regexp_replace(trim(coalesce(p_phone, '')), '\s+', '', 'g');
begin
  if v_phone = '' then
    return false;
  end if;
  return exists (
    select 1 from public.profiles
    where phone = v_phone
  );
end;
$$;

revoke all on function public.check_phone_registered(text) from public, anon;
grant execute on function public.check_phone_registered(text) to authenticated, anon;

-- 2. Helper function: check if a phone number is available for the current user to take
create or replace function public.check_phone_available(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_phone text := regexp_replace(trim(coalesce(p_phone, '')), '\s+', '', 'g');
begin
  if v_phone = '' then
    return true;
  end if;
  return not exists (
    select 1 from public.profiles
    where phone = v_phone
      and (v_user_id is null or user_id <> v_user_id)
  );
end;
$$;

revoke all on function public.check_phone_available(text) from public, anon;
grant execute on function public.check_phone_available(text) to authenticated, anon;

-- 3. Update save_personal_profile to disallow duplicate phone numbers across accounts
create or replace function public.save_personal_profile(
  p_display_name text,
  p_phone text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_name text := trim(coalesce(p_display_name, ''));
  v_phone text := nullif(regexp_replace(trim(coalesce(p_phone, '')), '\s+', '', 'g'), '');
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if char_length(v_name) not between 2 and 120 then
    raise exception 'Họ tên phải có từ 2 đến 120 ký tự' using errcode = '22023';
  end if;
  if v_phone is not null and v_phone !~ '^\+?[0-9]{9,15}$' then
    raise exception 'Số điện thoại không hợp lệ' using errcode = '22023';
  end if;

  -- Validate uniqueness: check if another account already registered this phone
  if v_phone is not null and exists (
    select 1 from public.profiles
    where phone = v_phone and user_id <> v_user_id
  ) then
    raise exception 'Số điện thoại này đã được sử dụng bởi tài khoản khác.' using errcode = '23505';
  end if;

  insert into public.profiles (user_id, display_name, phone)
    values (v_user_id, v_name, v_phone)
    on conflict (user_id) do update
      set display_name = excluded.display_name,
          phone = excluded.phone,
          updated_at = now();

  update public.expense_group_members as members
    set display_name = v_name, phone = v_phone
    where members.user_id = v_user_id;
end;
$$;

revoke all on function public.save_personal_profile(text, text)
  from public, anon;
grant execute on function public.save_personal_profile(text, text)
  to authenticated;

-- 4. Clean up any existing duplicate phone records by keeping the newest, and add a unique partial index
with duplicates as (
  select user_id, row_number() over (partition by phone order by updated_at desc nulls last) as rn
  from public.profiles
  where phone is not null and phone <> ''
)
update public.profiles
set phone = null
where user_id in (select user_id from duplicates where rn > 1);

with duplicates as (
  select user_id, row_number() over (partition by phone order by updated_at desc nulls last) as rn
  from public.profiles
  where phone is not null and phone <> ''
)
update public.expense_group_members
set phone = null
where user_id in (select user_id from duplicates where rn > 1);

create unique index if not exists profiles_phone_unique_idx
  on public.profiles (phone)
  where phone is not null and phone <> '';
