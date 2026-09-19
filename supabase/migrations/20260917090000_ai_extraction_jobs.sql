create table if not exists public.ai_extraction_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null,
  input_path text,
  input_kind text not null,
  input_mime_type text,
  status text not null default 'queued',
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  available_at timestamptz not null default now(),
  result jsonb,
  error_code text,
  input_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint ai_extraction_jobs_user_request_key unique (user_id, request_id),
  constraint ai_extraction_jobs_kind_check check (input_kind in ('text', 'image')),
  constraint ai_extraction_jobs_status_check check (status in ('queued', 'processing', 'succeeded', 'failed', 'cancelled')),
  constraint ai_extraction_jobs_attempts_check check (attempt_count >= 0 and max_attempts between 1 and 5),
  constraint ai_extraction_jobs_input_path_check check (input_path is null or input_path !~ '(^|/)\.\.?(/|$)')
);

create index if not exists ai_extraction_jobs_queue_idx
  on public.ai_extraction_jobs (status, available_at, created_at)
  where status in ('queued', 'processing');

alter table public.ai_extraction_jobs enable row level security;

revoke all on table public.ai_extraction_jobs from public, anon, authenticated;
grant select on table public.ai_extraction_jobs to authenticated;

drop policy if exists ai_extraction_jobs_owner_select on public.ai_extraction_jobs;
create policy ai_extraction_jobs_owner_select
  on public.ai_extraction_jobs for select to authenticated
  using ((select auth.uid()) = user_id);

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
set search_path = public
as $$
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
    select * into v_job
    from public.ai_extraction_jobs
    where user_id = v_user_id and request_id = trim(p_request_id);
    v_created := false;
  end if;
  return query select v_job.id, v_job.request_id, v_job.status, v_job.created_at, v_created;
end;
$$;

create or replace function public.cancel_ai_extraction_job(p_job_id uuid)
returns table (input_path text)
language plpgsql
security definer
set search_path = public
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
      input_path = null,
      input_expires_at = null,
      updated_at = now(),
      completed_at = now()
  from target
  where jobs.id = target.id
  returning target.input_path;
end;
$$;

create or replace function public.retry_ai_extraction_job(p_job_id uuid)
returns table (id uuid, status text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update public.ai_extraction_jobs
  set status = 'queued',
      attempt_count = 0,
      error_code = null,
      result = null,
      available_at = now(),
      updated_at = now(),
      completed_at = null
  where id = p_job_id
    and user_id = (select auth.uid())
    and status = 'failed'
    and input_path is not null
  returning ai_extraction_jobs.id, ai_extraction_jobs.status;
end;
$$;

create or replace function public.claim_ai_extraction_jobs(p_limit integer default 5)
returns setof public.ai_extraction_jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  update public.ai_extraction_jobs
  set status = case when attempt_count >= max_attempts then 'failed' else 'queued' end,
      error_code = case when attempt_count >= max_attempts then 'WORKER_TIMEOUT' else error_code end,
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

create or replace function public.finish_ai_extraction_job(
  p_job_id uuid,
  p_succeeded boolean,
  p_result jsonb default null,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  update public.ai_extraction_jobs
  set status = case
        when p_succeeded then 'succeeded'
        when attempt_count >= max_attempts then 'failed'
        else 'queued'
      end,
      result = case when p_succeeded then p_result else null end,
      error_code = case when p_succeeded then null else left(nullif(trim(p_error_code), ''), 80) end,
      input_expires_at = case
        when p_succeeded then now() + interval '1 day'
        when attempt_count >= max_attempts then now() + interval '7 days'
        else null
      end,
      available_at = case
        when p_succeeded or attempt_count >= max_attempts then available_at
        else now() + make_interval(secs => least(900, 30 * (2 ^ greatest(attempt_count - 1, 0))))
      end,
      updated_at = now(),
      completed_at = case
        when p_succeeded or attempt_count >= max_attempts then now()
        else null
      end
  where id = p_job_id and status = 'processing';
end;
$$;

create or replace function public.cleanup_ai_extraction_inputs()
returns table (input_path text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Worker role required' using errcode = '42501';
  end if;
  return query
  with expired as (
    select jobs.id, jobs.input_path
    from public.ai_extraction_jobs as jobs
    where jobs.input_path is not null
      and jobs.input_expires_at is not null
      and jobs.input_expires_at <= now()
    for update skip locked
  )
  update public.ai_extraction_jobs as jobs
  set input_path = null,
      input_expires_at = null,
      updated_at = now()
  from expired
  where jobs.id = expired.id
  returning expired.input_path;
end;
$$;

revoke all on function public.submit_ai_extraction_job(text, text, text, text) from public, anon;
revoke all on function public.cancel_ai_extraction_job(uuid) from public, anon;
revoke all on function public.retry_ai_extraction_job(uuid) from public, anon;
revoke all on function public.claim_ai_extraction_jobs(integer) from public, anon, authenticated;
revoke all on function public.finish_ai_extraction_job(uuid, boolean, jsonb, text) from public, anon, authenticated;
revoke all on function public.cleanup_ai_extraction_inputs() from public, anon, authenticated;
grant execute on function public.submit_ai_extraction_job(text, text, text, text) to authenticated;
grant execute on function public.cancel_ai_extraction_job(uuid) to authenticated;
grant execute on function public.retry_ai_extraction_job(uuid) to authenticated;
grant execute on function public.claim_ai_extraction_jobs(integer) to service_role;
grant execute on function public.finish_ai_extraction_job(uuid, boolean, jsonb, text) to service_role;
grant execute on function public.cleanup_ai_extraction_inputs() to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ai-inputs',
  'ai-inputs',
  false,
  52428800,
  array['text/plain', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists ai_inputs_owner_select on storage.objects;
create policy ai_inputs_owner_select
  on storage.objects for select to authenticated
  using (
    bucket_id = 'ai-inputs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists ai_inputs_owner_insert on storage.objects;
create policy ai_inputs_owner_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'ai-inputs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists ai_inputs_owner_delete on storage.objects;
create policy ai_inputs_owner_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'ai-inputs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
