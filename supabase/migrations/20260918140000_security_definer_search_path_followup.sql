alter function public.is_expense_group_member(uuid, uuid)
  set search_path = public, pg_temp;

alter function public.set_expense_group_member_role(uuid, uuid, text)
  set search_path = public, pg_temp;

alter function public.remove_expense_group_member(uuid, uuid)
  set search_path = public, pg_temp;

alter function public.leave_expense_group(uuid)
  set search_path = public, pg_temp;
