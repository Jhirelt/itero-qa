-- Which agent's evaluation each evaluator has open right now, so others can
-- see it before taking an assigned evaluation. One row per evaluator; the app
-- refreshes seen_at every 30s and treats rows older than 2 minutes as closed.
create table if not exists public.evaluation_presence (
  user_id uuid primary key default auth.uid() references public.profiles(id) on delete cascade,
  agent_id uuid references public.agents(id) on delete cascade,
  month date,
  opened_at timestamptz not null default now(),
  seen_at timestamptz not null default now()
);
create index if not exists evaluation_presence_agent_month_idx on public.evaluation_presence (agent_id, month);
alter table public.evaluation_presence enable row level security;
create policy "Authenticated can read evaluation_presence" on public.evaluation_presence
  for select to authenticated using (true);
create policy "Evaluator can add own evaluation_presence" on public.evaluation_presence
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Evaluator can update own evaluation_presence" on public.evaluation_presence
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, insert, update on public.evaluation_presence to authenticated;
