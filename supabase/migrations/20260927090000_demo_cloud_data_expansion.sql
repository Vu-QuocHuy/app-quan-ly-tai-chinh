-- Add demo-facing account data without copying or transforming existing local data.

alter table public.profiles
  add column if not exists theme_mode text not null default 'system'
    check (theme_mode in ('system', 'light', 'dark')),
  add column if not exists budget_alerts_enabled boolean not null default true,
  add column if not exists preferred_bank_app_id text
    check (preferred_bank_app_id is null or char_length(preferred_bank_app_id) <= 128);

create table public.invoice_attachments (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  invoice_id text not null,
  file_name text not null check (char_length(trim(file_name)) between 1 and 200),
  storage_path text not null,
  content_type text not null check (
    content_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')
  ),
  size_bytes bigint not null check (size_bytes between 1 and 15728640),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (user_id, id),
  unique (user_id, storage_path),
  foreign key (user_id, invoice_id)
    references public.invoices(user_id, id) on delete cascade,
  check (storage_path like user_id::text || '/%')
);

create index invoice_attachments_invoice_created_idx
  on public.invoice_attachments (user_id, invoice_id, created_at desc);

alter table public.invoice_attachments enable row level security;
revoke all on table public.invoice_attachments from public, anon;
grant select, insert, delete on table public.invoice_attachments to authenticated;

create policy invoice_attachments_owner_select on public.invoice_attachments
  for select to authenticated using ((select auth.uid()) = user_id);
create policy invoice_attachments_owner_insert on public.invoice_attachments
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy invoice_attachments_owner_delete on public.invoice_attachments
  for delete to authenticated using ((select auth.uid()) = user_id);

create table public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  title text not null default 'Trợ lý chi tiêu'
    check (char_length(trim(title)) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id)
);

create table public.chat_messages (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (char_length(id) between 1 and 128),
  conversation_id uuid not null,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(trim(content)) between 1 and 12000),
  citations jsonb not null default '[]'::jsonb
    check (jsonb_typeof(citations) = 'array'),
  created_at timestamptz not null default now(),
  primary key (user_id, id),
  foreign key (user_id, conversation_id)
    references public.chat_conversations(user_id, id) on delete cascade
);

create index chat_messages_conversation_created_idx
  on public.chat_messages (user_id, conversation_id, created_at desc, id desc);

alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;
revoke all on table public.chat_conversations from public, anon;
revoke all on table public.chat_messages from public, anon;
grant select, insert, update on table public.chat_conversations to authenticated;
grant select, insert, update, delete on table public.chat_messages to authenticated;

create policy chat_conversations_owner_all on public.chat_conversations
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy chat_messages_owner_all on public.chat_messages
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.chat_conversations c
      where c.id = chat_messages.conversation_id
        and c.user_id = chat_messages.user_id
    )
  );

create table public.qr_payment_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  bank_bin text not null default '' check (char_length(bank_bin) <= 24),
  account_number text not null default '' check (char_length(account_number) <= 128),
  recipient_name text not null default '' check (char_length(recipient_name) <= 255),
  memo text not null default '' check (char_length(memo) <= 1000),
  amount_vnd bigint check (amount_vnd between 0 and 9007199254740991),
  category_id text,
  bank_app_id text check (bank_app_id is null or char_length(bank_app_id) <= 128),
  status text not null check (
    status in ('scanned', 'bank_opened', 'user_confirmed', 'user_cancelled')
  ),
  invoice_id text,
  scanned_at timestamptz not null default now(),
  bank_opened_at timestamptz,
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index qr_payment_sessions_user_created_idx
  on public.qr_payment_sessions (user_id, scanned_at desc);
create index qr_payment_sessions_user_status_idx
  on public.qr_payment_sessions (user_id, status, scanned_at desc);

create table public.qr_payment_events (
  user_id uuid not null,
  id uuid not null,
  session_id uuid not null,
  event_type text not null check (
    event_type in (
      'scanned', 'bank_opened', 'user_confirmed', 'user_cancelled'
    )
  ),
  details jsonb not null default '{}'::jsonb
    check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  primary key (user_id, id),
  foreign key (user_id, session_id)
    references public.qr_payment_sessions(user_id, id) on delete cascade
);

create index qr_payment_events_session_created_idx
  on public.qr_payment_events (user_id, session_id, created_at);

alter table public.qr_payment_sessions enable row level security;
alter table public.qr_payment_events enable row level security;
revoke all on table public.qr_payment_sessions from public, anon;
revoke all on table public.qr_payment_events from public, anon;
grant select on table public.qr_payment_sessions to authenticated;
grant select on table public.qr_payment_events to authenticated;

create policy qr_payment_sessions_owner_select on public.qr_payment_sessions
  for select to authenticated using ((select auth.uid()) = user_id);
create policy qr_payment_events_owner_select on public.qr_payment_events
  for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.record_qr_payment_event(
  p_event_id uuid,
  p_session_id uuid,
  p_event_type text,
  p_bank_bin text,
  p_account_number text,
  p_recipient_name text,
  p_memo text,
  p_amount_vnd bigint,
  p_category_id text,
  p_bank_app_id text,
  p_invoice_id text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_status text;
  v_now timestamptz := statement_timestamp();
  v_details jsonb := '{}'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_event_id is null or p_session_id is null then
    raise exception 'QR event identifiers are required' using errcode = '22023';
  end if;
  if p_event_type is null or p_event_type not in ('scanned', 'bank_opened', 'user_confirmed', 'user_cancelled') then
    raise exception 'Unsupported QR event' using errcode = '22023';
  end if;
  if p_bank_bin is null or char_length(p_bank_bin) > 24
     or p_account_number is null or char_length(p_account_number) > 128
     or p_recipient_name is null or char_length(p_recipient_name) > 255
     or p_memo is null or char_length(p_memo) > 1000
     or (p_category_id is not null and char_length(p_category_id) > 128)
     or (p_amount_vnd is not null and p_amount_vnd not between 0 and 9007199254740991)
     or (p_bank_app_id is not null and char_length(p_bank_app_id) > 128)
     or (p_invoice_id is not null and char_length(p_invoice_id) > 128) then
    raise exception 'Invalid QR payment data' using errcode = '22023';
  end if;
  if p_event_type = 'user_confirmed' and p_invoice_id is null then
    raise exception 'A confirmed payment must reference its expense' using errcode = '22023';
  end if;
  if p_event_type = 'user_confirmed'
     and (p_amount_vnd is null or p_amount_vnd < 1 or p_category_id is null) then
    raise exception 'A confirmed payment requires amount and category' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.qr_payment_events e
    where e.user_id = v_user_id and e.id = p_event_id
  ) then
    return;
  end if;
  if p_event_type in ('user_confirmed', 'user_cancelled') and exists (
    select 1 from public.qr_payment_events e
    where e.user_id = v_user_id
      and e.session_id = p_session_id
      and e.event_type = p_event_type
  ) then
    return;
  end if;

  select s.status into v_status
  from public.qr_payment_sessions s
  where s.user_id = v_user_id and s.id = p_session_id
  for update;

  if not found then
    if p_event_type <> 'scanned' then
      raise exception 'QR session does not exist' using errcode = '22023';
    end if;
    insert into public.qr_payment_sessions (
      user_id, id, bank_bin, account_number, recipient_name, memo,
      amount_vnd, category_id, bank_app_id, status, updated_at
    ) values (
      v_user_id, p_session_id, p_bank_bin, p_account_number, p_recipient_name,
      p_memo, p_amount_vnd, p_category_id, p_bank_app_id, 'scanned', v_now
    );
    v_status := 'scanned';
  elsif v_status in ('user_confirmed', 'user_cancelled') then
    raise exception 'QR session is already resolved' using errcode = '22023';
  elsif p_event_type = 'scanned' and v_status <> 'scanned' then
    raise exception 'QR scan event is out of order' using errcode = '22023';
  end if;

  if p_event_type = 'bank_opened' then
    v_status := 'bank_opened';
    v_details := jsonb_build_object('bankAppId', p_bank_app_id);
  elsif p_event_type = 'user_confirmed' then
    v_status := 'user_confirmed';
    v_details := jsonb_build_object('invoiceId', p_invoice_id);
  elsif p_event_type = 'user_cancelled' then
    v_status := 'user_cancelled';
    v_details := '{}'::jsonb;
  end if;

  update public.qr_payment_sessions s
  set bank_bin = p_bank_bin,
      account_number = p_account_number,
      recipient_name = p_recipient_name,
      memo = p_memo,
      amount_vnd = p_amount_vnd,
      category_id = p_category_id,
      bank_app_id = coalesce(p_bank_app_id, s.bank_app_id),
      status = v_status,
      invoice_id = coalesce(p_invoice_id, s.invoice_id),
      bank_opened_at = case when p_event_type = 'bank_opened' then v_now else s.bank_opened_at end,
      resolved_at = case when p_event_type in ('user_confirmed', 'user_cancelled') then v_now else s.resolved_at end,
      updated_at = v_now
  where s.user_id = v_user_id and s.id = p_session_id;

  insert into public.qr_payment_events (user_id, id, session_id, event_type, details)
  values (v_user_id, p_event_id, p_session_id, p_event_type, v_details);
end;
$$;

revoke all on function public.record_qr_payment_event(
  uuid, uuid, text, text, text, text, text, bigint, text, text, text
) from public, anon;
grant execute on function public.record_qr_payment_event(
  uuid, uuid, text, text, text, text, text, bigint, text, text, text
) to authenticated;

-- The sync hardening migration intentionally removed direct profile writes.
-- These narrow RPCs update only the demo preferences owned by auth.uid().
create or replace function public.save_demo_profile_preferences(
  p_theme_mode text,
  p_budget_alerts_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_theme_mode is null or p_theme_mode not in ('system', 'light', 'dark')
     or p_budget_alerts_enabled is null then
    raise exception 'Invalid profile preferences' using errcode = '22023';
  end if;
  update public.profiles
  set theme_mode = p_theme_mode,
      budget_alerts_enabled = p_budget_alerts_enabled
  where user_id = v_user_id;
  if not found then
    raise exception 'Profile does not exist' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.save_demo_profile_preferences(text, boolean)
  from public, anon;
grant execute on function public.save_demo_profile_preferences(text, boolean)
  to authenticated;

create or replace function public.save_demo_preferred_bank_app(p_bank_app_id text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_bank_app_id is null or char_length(trim(p_bank_app_id)) not between 1 and 128 then
    raise exception 'Invalid bank app preference' using errcode = '22023';
  end if;
  update public.profiles
  set preferred_bank_app_id = trim(p_bank_app_id)
  where user_id = v_user_id;
  if not found then
    raise exception 'Profile does not exist' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.save_demo_preferred_bank_app(text)
  from public, anon;
grant execute on function public.save_demo_preferred_bank_app(text)
  to authenticated;

create or replace function public.touch_demo_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create trigger profiles_demo_updated_at
  before update on public.profiles
  for each row execute function public.touch_demo_updated_at();
create trigger chat_conversations_demo_updated_at
  before update on public.chat_conversations
  for each row execute function public.touch_demo_updated_at();
create trigger qr_payment_sessions_demo_updated_at
  before update on public.qr_payment_sessions
  for each row execute function public.touch_demo_updated_at();

revoke all on function public.touch_demo_updated_at() from public, anon, authenticated;
