drop function if exists public.retry_ai_extraction_job(uuid);

create function public.retry_ai_extraction_job(p_job_id uuid)
returns table (id uuid, status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_target_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select jobs.id into v_target_id
  from public.ai_extraction_jobs as jobs
  where jobs.id = p_job_id
    and jobs.user_id = v_user_id
    and jobs.status = 'failed'
    and jobs.input_path is not null
  for update;
  if v_target_id is null then
    return;
  end if;
  if not public.consume_ai_quota(30, 500) then
    raise exception 'AI retry quota exceeded' using errcode = 'P0001';
  end if;

  return query
  update public.ai_extraction_jobs
  set status = 'queued',
      attempt_count = 0,
      error_code = null,
      result = null,
      available_at = now(),
      updated_at = now(),
      completed_at = null
  where id = v_target_id
  returning ai_extraction_jobs.id, ai_extraction_jobs.status;
end;
$$;

revoke all on function public.retry_ai_extraction_job(uuid) from public, anon;
grant execute on function public.retry_ai_extraction_job(uuid) to authenticated;
