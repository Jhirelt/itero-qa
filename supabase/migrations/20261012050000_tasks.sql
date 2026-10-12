-- Shared task list for the QA team (Tasks tab).
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  priority text not null default 'medium' check (priority in ('high', 'medium', 'low')),
  due_date date,
  action text not null default '',
  responsible_name text not null default '',
  responsible_id uuid references public.profiles(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'completed')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  completed_by uuid,
  assigned_by uuid,
  seen_by_assignee boolean not null default true
);
create index if not exists tasks_status_idx on public.tasks (status);
create index if not exists tasks_responsible_idx on public.tasks (responsible_id) where not seen_by_assignee;

alter table public.tasks enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'tasks' and policyname = 'Staff read tasks') then
    create policy "Staff read tasks" on public.tasks for select using (public.is_staff());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'tasks' and policyname = 'Staff add tasks') then
    create policy "Staff add tasks" on public.tasks for insert with check (public.is_staff());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'tasks' and policyname = 'Staff edit tasks') then
    create policy "Staff edit tasks" on public.tasks for update using (public.is_staff()) with check (public.is_staff());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'tasks' and policyname = 'Staff delete tasks') then
    create policy "Staff delete tasks" on public.tasks for delete using (public.is_staff());
  end if;
end $$;
grant select, insert, update, delete on public.tasks to authenticated;

-- When someone gives a task to another person, that person gets a notification
-- (seen_by_assignee = false) until they open it. Completion is stamped too.
create or replace function public.tasks_track()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' or new.responsible_id is distinct from old.responsible_id then
    new.assigned_by := auth.uid();
    new.seen_by_assignee := new.responsible_id is null or new.responsible_id = auth.uid();
  end if;
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
    new.completed_at := now();
    new.completed_by := auth.uid();
  elsif new.status = 'pending' then
    new.completed_at := null;
    new.completed_by := null;
  end if;
  return new;
end;
$$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'tasks_track') then
    create trigger tasks_track before insert or update on public.tasks
      for each row execute function public.tasks_track();
  end if;
end $$;

-- Task settings (quick actions, extra responsible people) are shared and
-- editable by any QA profile, like the rubrics.
create or replace function public.save_shared_rubrics(patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed jsonb;
begin
  if not public.is_staff() then
    raise exception 'Only QA profiles can change the rubrics' using errcode = '42501';
  end if;
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into allowed
    from jsonb_each(coalesce(patch, '{}'::jsonb))
   where key in ('items', 'order', 'focusPoints', 'criteriaSeed', 'taskActions', 'taskPeople');
  insert into public.app_config (id, data, updated_by, updated_at)
  values (1, allowed, auth.uid(), now())
  on conflict (id) do update
    set data = coalesce(public.app_config.data, '{}'::jsonb) || excluded.data,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;
