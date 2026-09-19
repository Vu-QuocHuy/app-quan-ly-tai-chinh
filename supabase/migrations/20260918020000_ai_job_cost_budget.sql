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
declare
  v_user_id uuid := (select auth.uid());
  v_job public.ai_extraction_jobs;
  v_created boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_request_id is null or p_request_id !~ '^[A-Za-z0-9._:-]{8,128}$' then
    raise exception 'Invalid request id' using errcode = '22023';
  end if;
  if p_input_kind not in ('text', 'image') then
    raise exception 'Invalid input kind' using errcode = '22023';
  end if;
  if p_input_path is null or length(p_input_path) > 255 or
     p_input_path !~ ('^' || v_user_id::text || '/[0-9a-f-]{36}\.input$') then
    raise exception 'Invalid input path' using errcode = '22023';
  end if;
  if p_input_kind = 'text' and p_input_mime_type <> 'text/plain' then
    raise exception 'Invalid input mime type' using errcode = '22023';
  end if;
  if p_input_kind = 'image' and p_input_mime_type not in ('image/jpeg', 'image/png', 'image/webp') then
    raise exception 'Invalid input mime type' using errcode = '22023';
  end if;

  insert into public.ai_extraction_jobs (
    user_id, request_id, input_path, input_kind, input_mime_type
  ) values (
    v_user_id, p_request_id, p_input_path, p_input_kind, p_input_mime_type
  )
  on conflict (user_id, request_id) do nothing
  returning * into v_job;

  if found then
    if not public.consume_ai_quota(30, 500) then
      raise exception 'AI quota exceeded' using errcode = 'P0001';
    end if;
    if not public.consume_ai_cost_budget(5) then
      raise exception 'AI cost budget exceeded' using errcode = 'P0001';
    end if;
    v_created := true;
  else
    select * into v_job
    from public.ai_extraction_jobs
    where user_id = v_user_id and request_id = p_request_id;
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
  if not public.consume_ai_cost_budget(5) then
    raise exception 'AI retry cost budget exceeded' using errcode = 'P0001';
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

revoke all on function public.submit_ai_extraction_job(text, text, text, text)
  from public, anon;
grant execute on function public.submit_ai_extraction_job(text, text, text, text)
  to authenticated;

revoke all on function public.retry_ai_extraction_job(uuid) from public, anon;
grant execute on function public.retry_ai_extraction_job(uuid) to authenticated;
