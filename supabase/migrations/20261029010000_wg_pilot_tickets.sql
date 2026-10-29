-- White Glove pilot (June-September 2026): a one-off set of review exports kept apart from the regular White Glove data.
-- One row per ticket; the exports repeated identical rows, those are dropped when loading.
create table if not exists public.wg_pilot_tickets (
  ticket_number text primary key check (btrim(ticket_number) <> ''),
  source_month text,              -- export the ticket came from (June, July, August, September)
  ticket_owner text,
  mat_id text,
  account_name text,              -- "Name 1"
  subject text,
  opened_at timestamp,            -- "Date/Time Opened"
  opened_on date,                 -- "Opened Date"
  product_description text,
  asset_description text,
  serial_number text,
  install_date date,
  status text,
  issue_type text,
  sub_issue_type text,
  ticket_type text,
  product_family text
);
create index if not exists wg_pilot_tickets_customer on public.wg_pilot_tickets (mat_id, issue_type);
alter table public.wg_pilot_tickets enable row level security;
create policy "Members read wg_pilot_tickets" on public.wg_pilot_tickets
  for select to authenticated using ((select public.is_escalation_member()));
grant select on public.wg_pilot_tickets to authenticated;
