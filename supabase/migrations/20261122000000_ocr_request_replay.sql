create table public.ocr_request_replay (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null,
  fingerprint text not null,
  owner_token uuid not null,
  expires_at timestamptz not null,
  result jsonb,
  primary key (user_id, request_id)
);

alter table public.ocr_request_replay enable row level security;
revoke all on public.ocr_request_replay from public, anon, authenticated;
create index ocr_request_replay_expiry_idx on public.ocr_request_replay (expires_at);

create function public.ocr_replay(
  p_user_id uuid, p_request_id text, p_fingerprint text, p_owner_token uuid,
  p_action text, p_result jsonb default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  entry public.ocr_request_replay%rowtype;
begin
  if p_action = 'claim' then
    delete from public.ocr_request_replay
    where user_id = p_user_id and expires_at <= now();
    insert into public.ocr_request_replay
    values (p_user_id, p_request_id, p_fingerprint, p_owner_token,
            now() + interval '2 minutes', null)
    on conflict (user_id, request_id) do nothing;
    if found then
      return jsonb_build_object('status', 'claimed');
    end if;
    select * into entry from public.ocr_request_replay
    where user_id = p_user_id and request_id = p_request_id;
    if not found then
      return jsonb_build_object('status', 'pending');
    end if;
    if entry.fingerprint <> p_fingerprint then
      return jsonb_build_object('status', 'conflict');
    end if;
    if entry.result is not null then
      return jsonb_build_object('status', 'completed', 'result', entry.result);
    end if;
    return jsonb_build_object('status', 'pending');
  elsif p_action = 'complete' and p_result is not null then
    update public.ocr_request_replay
    set result = p_result, expires_at = now() + interval '24 hours'
    where user_id = p_user_id and request_id = p_request_id
      and owner_token = p_owner_token and result is null;
    return jsonb_build_object('status', case when found then 'completed' else 'stale' end);
  elsif p_action = 'release' then
    delete from public.ocr_request_replay
    where user_id = p_user_id and request_id = p_request_id
      and owner_token = p_owner_token and result is null;
    return jsonb_build_object('status', 'released');
  end if;
  raise exception 'Invalid OCR replay action';
end;
$$;

revoke all on function public.ocr_replay(uuid, text, text, uuid, text, jsonb)
from public, anon, authenticated;
grant execute on function public.ocr_replay(uuid, text, text, uuid, text, jsonb)
to service_role;

-- shortcut: without pg_cron, expired rows are pruned on the owner's next OCR request.
do $$
begin
  if to_regnamespace('cron') is not null then
    execute $schedule$
      select cron.schedule('ocr-request-replay-cleanup', '*/15 * * * *',
        'delete from public.ocr_request_replay where expires_at <= now()')
    $schedule$;
  end if;
end;
$$;
