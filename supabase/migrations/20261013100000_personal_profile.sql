alter table public.profiles
  add column phone text
    check (phone is null or phone ~ '^\+?[0-9]{9,15}$');

alter table public.expense_group_members
  add column phone text
    check (phone is null or phone ~ '^\+?[0-9]{9,15}$');

update public.expense_group_members as members
set phone = profiles.phone
from public.profiles as profiles
where members.user_id = profiles.user_id;

create or replace function public.fill_expense_group_member_phone()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.phone := (
    select profiles.phone from public.profiles as profiles
    where profiles.user_id = new.user_id
  );
  return new;
end;
$$;

revoke all on function public.fill_expense_group_member_phone()
  from public, anon, authenticated;

create trigger fill_expense_group_member_phone
  before insert on public.expense_group_members
  for each row execute function public.fill_expense_group_member_phone();

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
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
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
