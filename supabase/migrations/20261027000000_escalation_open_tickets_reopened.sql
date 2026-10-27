alter table public.escalation_open_tickets
  add column if not exists reopened_at timestamptz,
  add column if not exists prev_closed_at timestamp;
comment on column public.escalation_open_tickets.prev_closed_at is 'Closing date of the earlier closed ticket when this open ticket is a reopen; a later closing in an upload closes it again.';
