-- Call ID and time spent on each evaluation, time spent on each task.
alter table public.evaluations add column if not exists call_id text;
alter table public.evaluations add column if not exists time_spent_seconds integer;
alter table public.tasks add column if not exists time_spent_seconds integer;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'evaluations_time_spent_check') then
    alter table public.evaluations add constraint evaluations_time_spent_check check (time_spent_seconds is null or time_spent_seconds between 0 and 864000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tasks_time_spent_check') then
    alter table public.tasks add constraint tasks_time_spent_check check (time_spent_seconds is null or time_spent_seconds between 0 and 8640000);
  end if;
end $$;

create or replace function public.save_evaluation(payload jsonb)
 returns uuid
 language plpgsql
 set search_path to 'public'
as $function$
declare
  ev jsonb := payload->'evaluation';
  new_id uuid;
begin
  insert into evaluations (
    agent_id, evaluator_name, evaluator_id, call_date, ticket_id, call_reason,
    score, points_earned, points_possible, zero_triggered,
    assignment_id, kind, details, call_id, time_spent_seconds
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
    ev->'details',
    nullif(btrim(ev->>'call_id'), ''),
    (ev->>'time_spent_seconds')::integer
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
$function$;

create or replace function public.update_evaluation(eval_id uuid, payload jsonb)
 returns uuid
 language plpgsql
 set search_path to 'public'
as $function$
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
    call_id = case when ev ? 'call_id' then nullif(btrim(ev->>'call_id'), '') else call_id end,
    time_spent_seconds = case when ev ? 'time_spent_seconds' then (ev->>'time_spent_seconds')::integer else time_spent_seconds end,
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
$function$;

-- Release notes: the admin publishes them; QA staff get them in the bell until they read them.
create table if not exists public.release_notes (
  id uuid primary key default gen_random_uuid(),
  title text not null default '' check (char_length(title) <= 200),
  body text not null default '' check (char_length(body) <= 20000),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create table if not exists public.release_note_reads (
  note_id uuid not null references public.release_notes(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  read_at timestamptz not null default now(),
  primary key (note_id, user_id)
);
alter table public.release_notes enable row level security;
alter table public.release_note_reads enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'release_notes' and policyname = 'Staff read release notes') then
    create policy "Staff read release notes" on public.release_notes for select using (public.is_staff());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'release_notes' and policyname = 'Admin add release notes') then
    create policy "Admin add release notes" on public.release_notes for insert to authenticated with check (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'release_notes' and policyname = 'Admin delete release notes') then
    create policy "Admin delete release notes" on public.release_notes for delete to authenticated using (public.is_admin());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'release_note_reads' and policyname = 'Read own release note reads') then
    create policy "Read own release note reads" on public.release_note_reads for select using (user_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'release_note_reads' and policyname = 'Mark release notes read') then
    create policy "Mark release notes read" on public.release_note_reads for insert to authenticated with check (user_id = auth.uid() and public.is_staff());
  end if;
end $$;
grant select, insert, delete on public.release_notes to authenticated;
grant select, insert on public.release_note_reads to authenticated;
