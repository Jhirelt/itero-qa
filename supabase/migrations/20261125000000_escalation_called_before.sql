-- "Previous tickets" becomes a Yes/No question: had they called before about this error or related errors?
-- Tickets that already listed previous tickets start as Yes. Previous case handlers is removed entirely.
-- Root cause is now the ticket's sub-issue type on the page, so root_cause is no longer edited there.
alter table public.escalation_ticket_details add column if not exists called_before text check (called_before in ('Yes','No'));
update public.escalation_ticket_details set called_before = 'Yes' where called_before is null and nullif(btrim(previous_tickets), '') is not null;
alter table public.escalation_ticket_details drop column if exists previous_handlers;
