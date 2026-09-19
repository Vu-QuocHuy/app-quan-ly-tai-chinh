create or replace function public.record_client_error(
  p_source text,
  p_error_type text,
  p_message text,
  p_stack_trace text default null,
  p_fatal boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_window_started_at timestamptz;
  v_event_count integer;
  v_safe_message text;
  v_safe_stack_trace text;
begin
  if v_user_id is null then
    return false;
  end if;
  if p_source is null or char_length(p_source) not between 1 and 64 or p_source !~ '^[A-Za-z0-9_.-]+$' then
    raise exception 'Invalid error source' using errcode = '22023';
  end if;
  if p_error_type is null or char_length(p_error_type) not between 1 and 64 or p_error_type !~ '^[A-Za-z0-9_.-]+$' then
    raise exception 'Invalid error type' using errcode = '22023';
  end if;
  if p_message is null or char_length(p_message) not between 1 and 240 or p_message ~ '[[:cntrl:]]' then
    raise exception 'Invalid error message' using errcode = '22023';
  end if;
  if p_stack_trace is not null and (char_length(p_stack_trace) not between 1 and 4000 or p_stack_trace ~ '[[:cntrl:]]') then
    raise exception 'Invalid error stack' using errcode = '22023';
  end if;

  v_safe_message := p_message;
  v_safe_stack_trace := p_stack_trace;
  v_safe_message := regexp_replace(v_safe_message, '(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|service[_-]?role|token)[[:space:]]*[:=][[:space:]]*(bearer[[:space:]]+)?[^[:space:],;}]+', '[đã ẩn]', 'gi');
  v_safe_message := regexp_replace(v_safe_message, 'bearer[[:space:]]+[A-Za-z0-9._~+/=-]+', 'Bearer [đã ẩn]', 'gi');
  v_safe_message := regexp_replace(v_safe_message, 'https?://[^[:space:]]+', '[URL đã ẩn]', 'gi');
  v_safe_message := regexp_replace(v_safe_message, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email đã ẩn]', 'gi');
  v_safe_message := regexp_replace(v_safe_message, '(^|[^0-9])([+]?84|0)[0-9]{8,10}([^0-9]|$)', '\1[số điện thoại đã ẩn]\3', 'g');
  v_safe_message := regexp_replace(v_safe_message, '(^|[^0-9])[0-9]{10,14}([^0-9]|$)', '\1[mã số đã ẩn]\2', 'g');
  v_safe_stack_trace := regexp_replace(v_safe_stack_trace, '(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|service[_-]?role|token)[[:space:]]*[:=][[:space:]]*(bearer[[:space:]]+)?[^[:space:],;}]+', '\1=[đã ẩn]', 'gi');
  v_safe_stack_trace := regexp_replace(v_safe_stack_trace, 'bearer[[:space:]]+[A-Za-z0-9._~+/=-]+', 'Bearer [đã ẩn]', 'gi');
  v_safe_stack_trace := regexp_replace(v_safe_stack_trace, 'https?://[^[:space:]]+', '[URL đã ẩn]', 'gi');
  v_safe_stack_trace := regexp_replace(v_safe_stack_trace, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email đã ẩn]', 'gi');
  v_safe_stack_trace := regexp_replace(v_safe_stack_trace, '(^|[^0-9])([+]?84|0)[0-9]{8,10}([^0-9]|$)', '\1[số điện thoại đã ẩn]\3', 'g');
  v_safe_stack_trace := regexp_replace(v_safe_stack_trace, '(^|[^0-9])[0-9]{10,14}([^0-9]|$)', '\1[mã số đã ẩn]\2', 'g');

  insert into public.client_error_rate_limits (user_id)
    values (v_user_id)
    on conflict (user_id) do nothing;
  select limits.window_started_at, limits.event_count
    into v_window_started_at, v_event_count
    from public.client_error_rate_limits as limits
    where limits.user_id = v_user_id
    for update;
  if v_window_started_at <= now() - interval '1 minute' then
    update public.client_error_rate_limits
      set window_started_at = now(), event_count = 1
      where user_id = v_user_id;
  elsif v_event_count >= 20 then
    return false;
  else
    update public.client_error_rate_limits
      set event_count = event_count + 1
      where user_id = v_user_id;
  end if;

  insert into public.client_error_events (
    user_id, source, error_type, message, stack_trace, fatal
  ) values (
    v_user_id,
    p_source,
    p_error_type,
    left(v_safe_message, 240),
    case when v_safe_stack_trace is null then null else left(v_safe_stack_trace, 4000) end,
    coalesce(p_fatal, true)
  );
  return true;
end;
$$;
