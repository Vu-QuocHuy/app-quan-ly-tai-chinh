-- Keep group membership checks usable by RLS and trusted SECURITY DEFINER RPCs
-- without exposing an authenticated membership oracle for arbitrary user IDs.

create or replace function public.is_current_user_expense_group_member(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.expense_group_members as members
      where members.group_id = p_group_id
        and members.user_id = (select auth.uid())
    );
$function$;

-- Existing SECURITY DEFINER group RPCs still call this helper as its owner.
-- API roles must not call it with a user ID of their choice.
revoke all on function public.is_expense_group_member(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.is_current_user_expense_group_member(uuid)
  from public, anon, service_role;
grant execute on function public.is_current_user_expense_group_member(uuid)
  to authenticated;

drop policy if exists expense_group_members_member_select
  on public.expense_group_members;
create policy expense_group_members_member_select
  on public.expense_group_members
  for select to authenticated
  using (public.is_current_user_expense_group_member(group_id));

drop policy if exists expense_groups_member_select on public.expense_groups;
create policy expense_groups_member_select
  on public.expense_groups
  for select to authenticated
  using (public.is_current_user_expense_group_member(id));

drop policy if exists group_expenses_member_select on public.group_expenses;
create policy group_expenses_member_select
  on public.group_expenses
  for select to authenticated
  using (public.is_current_user_expense_group_member(group_id));

drop policy if exists group_expense_splits_member_select
  on public.group_expense_splits;
create policy group_expense_splits_member_select
  on public.group_expense_splits
  for select to authenticated
  using (
    public.is_current_user_expense_group_member(
      (
        select expenses.group_id
        from public.group_expenses as expenses
        where expenses.id = group_expense_splits.expense_id
      )
    )
  );

drop policy if exists group_audit_events_member_select
  on public.group_audit_events;
create policy group_audit_events_member_select
  on public.group_audit_events
  for select to authenticated
  using (public.is_current_user_expense_group_member(group_id));
