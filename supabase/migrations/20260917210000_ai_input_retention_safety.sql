create or replace function public.cancel_ai_extraction_job(p_job_id uuid)
returns table (input_path text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  with target as (
    select jobs.id, jobs.input_path
    from public.ai_extraction_jobs as jobs
    where jobs.id = p_job_id
      and jobs.user_id = (select auth.uid())
      and jobs.status in ('queued', 'processing')
    for update
  )
  update public.ai_extraction_jobs as jobs
  set status = 'cancelled',
      input_expires_at = case
        when target.input_path is null then null
        else now() + interval '1 day'
      end,
      updated_at = now(),
      completed_at = now()
  from target
  where jobs.id = target.id
  returning target.input_path;
end;
$$;

create or replace function public.claim_ai_extraction_jobs(p_limit integer default 5)
returns setof public.ai_extraction_jobs
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  update public.ai_extraction_jobs
  set status = case when attempt_count >= max_attempts then 'failed' else 'queued' end,
      error_code = case when attempt_count >= max_attempts then 'WORKER_TIMEOUT' else error_code end,
      input_expires_at = case
        when attempt_count >= max_attempts and input_path is not null
          then now() + interval '7 days'
        else input_expires_at
      end,
      completed_at = case when attempt_count >= max_attempts then now() else null end,
      updated_at = now()
  where status = 'processing'
    and updated_at < now() - interval '10 minutes';
  return query
  with picked as (
    select jobs.id
    from public.ai_extraction_jobs as jobs
    where jobs.status = 'queued'
      and jobs.available_at <= now()
    order by jobs.created_at
    for update skip locked
    limit least(greatest(coalesce(p_limit, 5), 1), 10)
  )
  update public.ai_extraction_jobs as jobs
  set status = 'processing',
      attempt_count = jobs.attempt_count + 1,
      updated_at = now()
  from picked
  where jobs.id = picked.id
  returning jobs.*;
end;
$$;
