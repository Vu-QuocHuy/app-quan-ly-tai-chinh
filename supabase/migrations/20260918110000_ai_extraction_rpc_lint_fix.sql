create or replace function public.submit_ai_extraction_job(
  p_request_id text,
  p_input_path text,
  p_input_kind text,
  p_input_mime_type text default null
)
returns table (
  id uuid,
  request_id text,
  status text,
  created_at timestamptz,
  created boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_user_id uuid := (select auth.uid());
  v_job public.ai_extraction_jobs;
  v_created boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_request_id is null or length(trim(p_request_id)) < 8 or length(p_request_id) > 128 then
    raise exception 'Invalid request id' using errcode = '22023';
  end if;
  if p_input_kind not in ('text', 'image') then
    raise exception 'Invalid input kind' using errcode = '22023';
  end if;
  if p_input_path is null or split_part(p_input_path, '/', 1) <> v_user_id::text then
    raise exception 'Invalid input path' using errcode = '22023';
  end if;
  insert into public.ai_extraction_jobs (
    user_id, request_id, input_path, input_kind, input_mime_type
  ) values (
    v_user_id, trim(p_request_id), p_input_path, p_input_kind, nullif(trim(p_input_mime_type), '')
  )
  on conflict (user_id, request_id) do nothing
  returning * into v_job;
  if found then
    v_created := true;
  else
    select jobs.* into v_job
    from public.ai_extraction_jobs as jobs
    where jobs.user_id = v_user_id and jobs.request_id = trim(p_request_id);
    v_created := false;
  end if;
  return query select v_job.id, v_job.request_id, v_job.status, v_job.created_at, v_created;
end;
$$;

create or replace function public.retry_ai_extraction_job(p_job_id uuid)
returns table (id uuid, status text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  update public.ai_extraction_jobs as jobs
  set status = 'queued',
      attempt_count = 0,
      error_code = null,
      result = null,
      available_at = now(),
      updated_at = now(),
      completed_at = null
  where jobs.id = p_job_id
    and jobs.user_id = (select auth.uid())
    and jobs.status = 'failed'
    and jobs.input_path is not null
  returning jobs.id, jobs.status;
end;
$$;
