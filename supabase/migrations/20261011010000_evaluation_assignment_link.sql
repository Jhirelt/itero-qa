-- Link evaluations to who did them, to the assignment they fulfil, and keep
-- the full evaluation (answers, texts, summary) so it can be viewed and edited.
alter table public.evaluations
  add column if not exists evaluator_id uuid default auth.uid() references public.profiles(id) on delete set null,
  add column if not exists assignment_id uuid references public.evaluation_assignments(id) on delete set null,
  add column if not exists kind text check (kind in ('call', 'ticket')),
  add column if not exists details jsonb,
  add column if not exists updated_at timestamptz;

create index if not exists evaluations_evaluator_id_idx on public.evaluations (evaluator_id);
create index if not exists evaluations_assignment_id_idx on public.evaluations (assignment_id);

-- Save: same as before plus the new columns.
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
    agent_id, evaluator_name, evaluator_id, call_date, ticket_id, call_reason,
    score, points_earned, points_possible, zero_triggered,
    assignment_id, kind, details
  ) values (
    (ev->>'agent_id')::uuid,
    ev->>'evaluator_name',
    auth.uid(),
    (ev->>'call_date')::date,
    ev->>'ticket_id',
    ev->>'call_reason',
    (ev->>'score')::numeric,
    (ev->>'points_earned')::numeric,
    (ev->>'points_possible')::numeric,
    coalesce((ev->>'zero_triggered')::boolean, false),
    nullif(ev->>'assignment_id', '')::uuid,
    nullif(ev->>'kind', ''),
    ev->'details'
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

-- Edit a saved evaluation in one transaction: update the row and replace its
-- section scores and deductions. Row level security decides who may do it.
create or replace function public.update_evaluation(eval_id uuid, payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  ev jsonb := payload->'evaluation';
  touched int;
begin
  update evaluations set
    call_date = (ev->>'call_date')::date,
    ticket_id = ev->>'ticket_id',
    call_reason = ev->>'call_reason',
    score = (ev->>'score')::numeric,
    points_earned = (ev->>'points_earned')::numeric,
    points_possible = (ev->>'points_possible')::numeric,
    zero_triggered = coalesce((ev->>'zero_triggered')::boolean, false),
    details = ev->'details',
    updated_at = now()
  where id = eval_id;
  get diagnostics touched = row_count;
  if touched = 0 then
    raise exception 'You can only edit evaluations you did (or any, as an admin).' using errcode = '42501';
  end if;

  delete from evaluation_sections where evaluation_id = eval_id;
  delete from evaluation_deductions where evaluation_id = eval_id;

  insert into evaluation_sections (evaluation_id, section_key, section_title, points_earned, points_possible)
  select eval_id, s->>'section_key', s->>'section_title', (s->>'points_earned')::numeric, (s->>'points_possible')::numeric
  from jsonb_array_elements(coalesce(payload->'sections', '[]'::jsonb)) as s;

  insert into evaluation_deductions (evaluation_id, section_key, rubric_label, points_lost)
  select eval_id, d->>'section_key', d->>'rubric_label', (d->>'points_lost')::numeric
  from jsonb_array_elements(coalesce(payload->'deductions', '[]'::jsonb)) as d;

  return eval_id;
end;
$$;

revoke execute on function public.update_evaluation(uuid, jsonb) from public, anon;
grant execute on function public.update_evaluation(uuid, jsonb) to authenticated;

-- Take over an assignment (e.g. it was Braulio's and someone else evaluates it).
create or replace function public.take_assignment(assignment uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'Sign in with a QA profile first.' using errcode = '42501';
  end if;
  update evaluation_assignments set assignee_id = auth.uid() where id = assignment;
end;
$$;

revoke execute on function public.take_assignment(uuid) from public, anon;
grant execute on function public.take_assignment(uuid) to authenticated;

-- The person who did an evaluation may edit or delete it (admins already can).
create policy "Evaluator can update own evaluations" on public.evaluations
  for update to authenticated
  using (evaluator_id = (select auth.uid()))
  with check (evaluator_id = (select auth.uid()));

create policy "Evaluator can delete own evaluations" on public.evaluations
  for delete to authenticated
  using (evaluator_id = (select auth.uid()));

create policy "Evaluator can update own evaluation_sections" on public.evaluation_sections
  for update to authenticated
  using (exists (select 1 from evaluations e where e.id = evaluation_id and e.evaluator_id = (select auth.uid())));

create policy "Evaluator can delete own evaluation_sections" on public.evaluation_sections
  for delete to authenticated
  using (exists (select 1 from evaluations e where e.id = evaluation_id and e.evaluator_id = (select auth.uid())));

create policy "Evaluator can delete own evaluation_deductions" on public.evaluation_deductions
  for delete to authenticated
  using (exists (select 1 from evaluations e where e.id = evaluation_id and e.evaluator_id = (select auth.uid())));
