-- Tasks can be put on hold (status stays 'pending' so the pending list keeps them).
alter table public.tasks add column if not exists on_hold boolean not null default false;

-- Rows created by a test run are flagged so an admin can remove exactly those
-- (Configuration > Remove test data) without touching real data.
alter table public.evaluations add column if not exists is_test boolean not null default false;
alter table public.evaluation_assignments add column if not exists is_test boolean not null default false;
alter table public.tasks add column if not exists is_test boolean not null default false;

-- Inserting a task outside a signed-in session (auth.uid() is null) failed on
-- the not-null seen_by_assignee; treat it as unseen by the assignee instead.
create or replace function public.tasks_track()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' or new.responsible_id is distinct from old.responsible_id then
    new.assigned_by := auth.uid();
    new.seen_by_assignee := coalesce(new.responsible_id is null or new.responsible_id = auth.uid(), false);
  end if;
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
    new.completed_at := coalesce(new.completed_at, now());
    new.completed_by := coalesce(auth.uid(), new.completed_by);
  elsif new.status = 'pending' then
    new.completed_at := null;
    new.completed_by := null;
  end if;
  return new;
end;
$$;
