-- Open escalations entered on the page (the Salesforce export only has closed ones).
-- The PDF report and the summary count them as open until the ticket shows up closed in an upload.
create table if not exists public.escalation_open_tickets (
  ticket_number text primary key check (btrim(ticket_number) <> ''),
  escalation_type text not null default 'CSC' check (escalation_type in ('Business','CSC')),
  opened_on date,
  account_name text,
  subject text,
  scanner_model text,
  status_note text,
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now()
);
alter table public.escalation_open_tickets enable row level security;
create policy "Members read escalation_open_tickets" on public.escalation_open_tickets
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Uploaders add escalation_open_tickets" on public.escalation_open_tickets
  for insert to authenticated with check ((select public.is_escalation_uploader()));
create policy "Uploaders edit escalation_open_tickets" on public.escalation_open_tickets
  for update to authenticated using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()));
create policy "Uploaders delete escalation_open_tickets" on public.escalation_open_tickets
  for delete to authenticated using ((select public.is_escalation_uploader()));
grant select, insert, update, delete on public.escalation_open_tickets to authenticated;
