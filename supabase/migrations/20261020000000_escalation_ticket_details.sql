-- Details filled in on the page for each ticket. Kept apart from escalation_tickets
-- so a new upload of the same ticket never overwrites them.
create table if not exists public.escalation_ticket_details (
  ticket_number text primary key check (btrim(ticket_number) <> ''),
  avoidable text check (avoidable in ('Yes','No')),
  root_cause text,
  origin text,
  previous_tickets text,
  previous_handlers text,
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now()
);
alter table public.escalation_ticket_details enable row level security;

create policy "Members read escalation_ticket_details" on public.escalation_ticket_details
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Uploaders add escalation_ticket_details" on public.escalation_ticket_details
  for insert to authenticated with check ((select public.is_escalation_uploader()));
create policy "Uploaders edit escalation_ticket_details" on public.escalation_ticket_details
  for update to authenticated using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()));

grant select, insert, update on public.escalation_ticket_details to authenticated;
