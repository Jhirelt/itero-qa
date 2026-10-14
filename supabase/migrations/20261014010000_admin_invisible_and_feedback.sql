-- 1) Admins are invisible to evaluators: evaluators cannot read admin profiles,
--    admin presence, or tasks whose responsible is an admin. Whatever an admin
--    does leaves no name or notification behind for evaluators.
-- 2) Suggestions box: QA staff send ideas for the app; admins read them.

create or replace function public.is_admin_id(uid uuid) returns boolean
  language sql stable security definer set search_path to 'public'
as $$ select uid is not null and exists (select 1 from profiles where id = uid and role = 'admin'); $$;
grant execute on function public.is_admin_id(uuid) to authenticated;

alter policy "Authenticated users can read profiles" on public.profiles
  using ((select public.is_admin()) or id = (select auth.uid()) or ((select public.is_staff()) and role <> 'admin'));

alter policy "Staff read tasks" on public.tasks
  using (public.is_admin() or (public.is_staff() and not public.is_admin_id(responsible_id)));

alter policy "Authenticated can read evaluation_presence" on public.evaluation_presence
  using ((select public.is_admin()) or ((select public.is_staff()) and not public.is_admin_id(user_id)));

-- Tasks an admin creates, gives or completes carry no admin id and never ring
-- the evaluator's bell: they just show up assigned.
create or replace function public.tasks_track()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  by_admin boolean := public.is_admin();
begin
  new.updated_at := now();
  if tg_op = 'INSERT' and by_admin then
    new.created_by := null;
  end if;
  if tg_op = 'INSERT' or new.responsible_id is distinct from old.responsible_id then
    if by_admin then
      new.assigned_by := null;
      new.seen_by_assignee := true;
    else
      new.assigned_by := auth.uid();
      new.seen_by_assignee := coalesce(new.responsible_id is null or new.responsible_id = auth.uid(), false);
    end if;
  end if;
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
    new.completed_at := coalesce(new.completed_at, now());
    new.completed_by := case when by_admin then null else coalesce(auth.uid(), new.completed_by) end;
  elsif new.status = 'pending' then
    new.completed_at := null;
    new.completed_by := null;
  end if;
  return new;
end;
$$;

-- Evaluations an admin saves show as "QA" to evaluators, and an admin's edits
-- do not change the "Last edited" time evaluators see.
create or replace function public.evaluations_hide_admin()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.is_admin() then
    if tg_op = 'INSERT' then
      new.evaluator_name := 'QA';
    else
      new.updated_at := old.updated_at;
    end if;
  end if;
  return new;
end;
$$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'evaluations_hide_admin') then
    create trigger evaluations_hide_admin before insert or update on public.evaluations
      for each row execute function public.evaluations_hide_admin();
  end if;
end $$;

-- Suggestions for the app.
create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  author_name text not null default '',
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  status text not null default 'new' check (status in ('new', 'done')),
  created_at timestamptz not null default now()
);
alter table public.app_feedback enable row level security;
create policy "Staff send app_feedback" on public.app_feedback
  for insert to authenticated with check ((select public.is_staff()) and created_by = (select auth.uid()));
create policy "Admins or the author read app_feedback" on public.app_feedback
  for select to authenticated using ((select public.is_admin()) or created_by = (select auth.uid()));
create policy "Admins update app_feedback" on public.app_feedback
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "Admins remove app_feedback" on public.app_feedback
  for delete to authenticated using ((select public.is_admin()));
grant select, insert, update, delete on public.app_feedback to authenticated;

-- Personal options now also remember whether the "Take tour?" notice is off.
create or replace function public.set_my_prefs(patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  update public.profiles
     set prefs = coalesce(prefs, '{}'::jsonb) || (
       select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
         from jsonb_each(coalesce(patch, '{}'::jsonb))
        where key in ('quickNotes', 'focusPoints', 'tourOff') and jsonb_typeof(value) = 'boolean')
   where id = auth.uid()
  returning prefs into result;
  return result;
end;
$$;
