-- Escalations becomes a weekly report fed by Excel uploads (the Salesforce
-- "Closed CSC escalations" export). Each upload is recorded, and its rows are
-- upserted by ticket number, so re-uploading an overlapping export updates
-- tickets instead of duplicating them. Access stays the escalation_members list.

create table public.escalation_uploads (
  id bigint generated always as identity primary key,
  file_name text not null,
  row_count integer not null default 0,
  new_count integer not null default 0,
  updated_count integer not null default 0,
  uploaded_by uuid default auth.uid() references auth.users(id) on delete set null,
  uploaded_at timestamptz not null default now()
);

create table public.escalation_tickets (
  ticket_number text primary key check (btrim(ticket_number) <> ''),
  issue_type text,
  sub_issue_type text,
  priority text,
  opened_at timestamp,          -- as shown in the export (no time zone)
  closed_at timestamp,
  solution_provided text,
  account_name text,
  subject text,
  ticket_type text,
  complaint_sub_type text,
  internal_requestor text,
  extra jsonb not null default '{}'::jsonb,   -- any column the page doesn't know yet
  first_upload_id bigint references public.escalation_uploads(id) on delete set null,
  last_upload_id bigint references public.escalation_uploads(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index escalation_tickets_closed_at_idx on public.escalation_tickets (closed_at);
create index escalation_tickets_opened_at_idx on public.escalation_tickets (opened_at);

alter table public.escalation_uploads enable row level security;
alter table public.escalation_tickets enable row level security;

create policy "Members read escalation_uploads" on public.escalation_uploads
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Members add escalation_uploads" on public.escalation_uploads
  for insert to authenticated with check ((select public.is_escalation_member()));
create policy "Members edit escalation_uploads" on public.escalation_uploads
  for update to authenticated using ((select public.is_escalation_member())) with check ((select public.is_escalation_member()));

create policy "Members read escalation_tickets" on public.escalation_tickets
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Members add escalation_tickets" on public.escalation_tickets
  for insert to authenticated with check ((select public.is_escalation_member()));
create policy "Members edit escalation_tickets" on public.escalation_tickets
  for update to authenticated using ((select public.is_escalation_member())) with check ((select public.is_escalation_member()));

grant select, insert, update on public.escalation_uploads, public.escalation_tickets to authenticated;
