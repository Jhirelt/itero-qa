-- Escalations tracker (escalations/index.html). Replaces the
-- "Lumina Opened Escalations" Excel: one row per escalation plus a running
-- log of updates. Same staff accounts as QA: anyone with a profile can read
-- and write; only admins delete escalations.

create table if not exists public.escalations (
  id bigint generated always as identity primary key,
  ticket text not null check (btrim(ticket) <> ''),
  subject text,
  opened_on date not null default current_date,
  requested_by text,
  customer text,
  customer_type text,
  serial_number text,
  software_version text,
  poc text,
  team text,
  rca text,
  issue text,
  solution text,
  category text,
  jira text,
  assigned_to_jira boolean not null default false,
  status text not null default 'Open' check (status in (
    'Needs Review', 'Open', 'In Progress', 'Under Investigation',
    'Waiting Replacement', 'Waiting Customer', 'Monitoring', 'Resolved'
  )),
  status_note text,
  closed_on date,
  source text not null default 'app',
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
create index if not exists escalations_ticket_idx on public.escalations (ticket);
create index if not exists escalations_opened_on_idx on public.escalations (opened_on desc);
create index if not exists escalations_status_idx on public.escalations (status);

create table if not exists public.escalation_updates (
  id bigint generated always as identity primary key,
  escalation_id bigint not null references public.escalations(id) on delete cascade,
  body text not null check (btrim(body) <> ''),
  author_id uuid default auth.uid() references auth.users(id) on delete set null,
  author_name text,
  created_at timestamptz not null default now()
);
create index if not exists escalation_updates_escalation_idx on public.escalation_updates (escalation_id, created_at desc);

-- Keeps updated_at/updated_by current and closed_on in step with the status:
-- set the day it becomes Resolved, cleared if it is reopened.
create or replace function public.escalations_touch() returns trigger
  language plpgsql set search_path to 'public'
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then new.updated_by := auth.uid(); end if;
  if new.status = 'Resolved' and new.closed_on is null
     and (tg_op = 'INSERT' or old.status is distinct from 'Resolved') then
    new.closed_on := current_date;
  elsif new.status <> 'Resolved' then
    new.closed_on := null;
  end if;
  return new;
end;
$$;
create trigger escalations_touch before insert or update on public.escalations
  for each row execute function public.escalations_touch();

alter table public.escalations enable row level security;
alter table public.escalation_updates enable row level security;

create policy "Staff read escalations" on public.escalations
  for select to authenticated using ((select public.is_staff()));
create policy "Staff add escalations" on public.escalations
  for insert to authenticated with check ((select public.is_staff()));
create policy "Staff edit escalations" on public.escalations
  for update to authenticated using ((select public.is_staff())) with check ((select public.is_staff()));
create policy "Admins delete escalations" on public.escalations
  for delete to authenticated using ((select public.is_admin()));

create policy "Staff read escalation_updates" on public.escalation_updates
  for select to authenticated using ((select public.is_staff()));
create policy "Staff add escalation_updates" on public.escalation_updates
  for insert to authenticated with check ((select public.is_staff()) and author_id = (select auth.uid()));
create policy "Authors and admins delete escalation_updates" on public.escalation_updates
  for delete to authenticated using (author_id = (select auth.uid()) or (select public.is_admin()));

grant select, insert, update, delete on public.escalations, public.escalation_updates to authenticated;

-- Live dashboard: the page listens for changes on both tables.
alter publication supabase_realtime add table public.escalations, public.escalation_updates;
