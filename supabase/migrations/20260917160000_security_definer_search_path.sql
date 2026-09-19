-- Keep privileged RPCs deterministic even when a caller creates temporary objects.
alter function public.consume_ai_quota(integer, integer)
  set search_path = public, pg_temp;

alter function public.submit_ai_extraction_job(text, text, text, text)
  set search_path = public, pg_temp;
alter function public.cancel_ai_extraction_job(uuid)
  set search_path = public, pg_temp;
alter function public.retry_ai_extraction_job(uuid)
  set search_path = public, pg_temp;
alter function public.claim_ai_extraction_jobs(integer)
  set search_path = public, pg_temp;
alter function public.finish_ai_extraction_job(uuid, boolean, jsonb, text)
  set search_path = public, pg_temp;
alter function public.cleanup_ai_extraction_inputs()
  set search_path = public, pg_temp;

alter function public.create_expense_group(text)
  set search_path = public, pg_temp;
alter function public.join_expense_group(text)
  set search_path = public, pg_temp;
alter function public.create_group_expense(uuid, text, bigint, uuid[])
  set search_path = public, pg_temp;
alter function public.create_group_expense_custom(uuid, text, bigint, jsonb)
  set search_path = public, pg_temp;
alter function public.settle_group_split(uuid)
  set search_path = public, pg_temp;
