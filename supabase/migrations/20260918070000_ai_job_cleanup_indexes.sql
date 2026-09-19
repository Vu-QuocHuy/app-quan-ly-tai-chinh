create index if not exists ai_extraction_jobs_input_cleanup_idx
  on public.ai_extraction_jobs (input_expires_at, id)
  where input_path is not null and input_expires_at is not null;

create index if not exists ai_extraction_jobs_terminal_cleanup_idx
  on public.ai_extraction_jobs (completed_at, id)
  where status in ('succeeded', 'failed', 'cancelled')
    and completed_at is not null
    and input_path is null;
