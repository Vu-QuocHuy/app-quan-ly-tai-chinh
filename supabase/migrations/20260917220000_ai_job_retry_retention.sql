create or replace function public.retry_ai_extraction_job(p_job_id uuid)
returns table (id uuid, status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  update public.ai_extraction_jobs
  set status = 'queued',
      attempt_count = 0,
      error_code = null,
      result = null,
      input_expires_at = null,
      available_at = now(),
      updated_at = now(),
      completed_at = null
  where id = p_job_id
    and user_id = (select auth.uid())
    and status = 'failed'
    and input_path is not null
    and (input_expires_at is null or input_expires_at > now())
  returning ai_extraction_jobs.id, ai_extraction_jobs.status;
end;
$$;
