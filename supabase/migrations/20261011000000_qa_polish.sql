-- 1) Save an evaluation, its section scores and its deductions in one
--    transaction, so a failed save never leaves a half-written evaluation.
--    SECURITY INVOKER: the caller's existing row level security still applies.
create or replace function public.save_evaluation(payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  ev jsonb := payload->'evaluation';
  new_id uuid;
begin
  insert into evaluations (
    agent_id, evaluator_name, call_date, ticket_id, call_reason,
    score, points_earned, points_possible, zero_triggered
  ) values (
    (ev->>'agent_id')::uuid,
    ev->>'evaluator_name',
    (ev->>'call_date')::date,
    ev->>'ticket_id',
    ev->>'call_reason',
    (ev->>'score')::numeric,
    (ev->>'points_earned')::numeric,
    (ev->>'points_possible')::numeric,
    coalesce((ev->>'zero_triggered')::boolean, false)
  )
  returning id into new_id;

  insert into evaluation_sections (evaluation_id, section_key, section_title, points_earned, points_possible)
  select new_id, s->>'section_key', s->>'section_title', (s->>'points_earned')::numeric, (s->>'points_possible')::numeric
  from jsonb_array_elements(coalesce(payload->'sections', '[]'::jsonb)) as s;

  insert into evaluation_deductions (evaluation_id, section_key, rubric_label, points_lost)
  select new_id, d->>'section_key', d->>'rubric_label', (d->>'points_lost')::numeric
  from jsonb_array_elements(coalesce(payload->'deductions', '[]'::jsonb)) as d;

  return new_id;
end;
$$;

revoke execute on function public.save_evaluation(jsonb) from public, anon;
grant execute on function public.save_evaluation(jsonb) to authenticated;

-- 2) Only admins may change the shared rubric / scenario configuration.
--    Everyone signed in can still read it.
drop policy if exists "Authenticated can insert app_config" on public.app_config;
drop policy if exists "Authenticated can update app_config" on public.app_config;

create policy "Admin can insert app_config" on public.app_config
  for insert to authenticated
  with check ((select public.is_admin()));

create policy "Admin can update app_config" on public.app_config
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- 3) Evaluation assignments: any QA profile can assign one of an agent's
--    monthly evaluation slots (1-4, or more) to themselves or to another
--    profile, as a call or a ticket evaluation.
create table if not exists public.evaluation_assignments (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.agents(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  slot integer not null check (slot between 1 and 20),
  assignee_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('call', 'ticket')),
  assigned_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (agent_id, month, slot)
);

create index if not exists evaluation_assignments_month_idx on public.evaluation_assignments (month);
create index if not exists evaluation_assignments_assignee_idx on public.evaluation_assignments (assignee_id);
create index if not exists evaluation_assignments_assigned_by_idx on public.evaluation_assignments (assigned_by);

alter table public.evaluation_assignments enable row level security;

create policy "Authenticated can read evaluation_assignments" on public.evaluation_assignments
  for select to authenticated
  using (true);

create policy "Authenticated can create own evaluation_assignments" on public.evaluation_assignments
  for insert to authenticated
  with check (assigned_by = (select auth.uid()));

create policy "Assigner, assignee or admin can remove evaluation_assignments" on public.evaluation_assignments
  for delete to authenticated
  using (
    assigned_by = (select auth.uid())
    or assignee_id = (select auth.uid())
    or (select public.is_admin())
  );
