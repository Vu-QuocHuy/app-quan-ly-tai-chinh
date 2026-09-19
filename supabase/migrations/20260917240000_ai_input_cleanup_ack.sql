drop function if exists public.cleanup_ai_extraction_inputs();

create function public.cleanup_ai_extraction_inputs()
returns table (id uuid, input_path text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  return query
  select jobs.id, jobs.input_path
  from public.ai_extraction_jobs as jobs
  where jobs.input_path is not null
    and jobs.input_expires_at is not null
    and jobs.input_expires_at <= now()
  order by jobs.input_expires_at, jobs.id
  for update skip locked;
end;
$$;

create function public.mark_ai_extraction_input_deleted(
  p_job_id uuid,
  p_input_path text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_deleted boolean;
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  with updated as (
    update public.ai_extraction_jobs
    set input_path = null,
        input_expires_at = null,
        updated_at = now()
    where id = p_job_id
      and input_path = p_input_path
      and input_expires_at is not null
      and input_expires_at <= now()
    returning id
  )
  select exists(select 1 from updated) into v_deleted;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_ai_extraction_inputs() from public, anon, authenticated;
revoke all on function public.mark_ai_extraction_input_deleted(uuid, text) from public, anon, authenticated;
grant execute on function public.cleanup_ai_extraction_inputs() to service_role;
grant execute on function public.mark_ai_extraction_input_deleted(uuid, text) to service_role;
