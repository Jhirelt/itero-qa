-- Scanner model picked from a list on each ticket.
alter table public.escalation_ticket_details add column if not exists scanner_model text;
