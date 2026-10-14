-- Supervisor and role for each agent (options are edited in Configuration).
alter table public.agents
  add column if not exists supervisor text,
  add column if not exists role text;
