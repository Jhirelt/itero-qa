-- A ticket number that shows up again in a later upload replaces the stored
-- row and is tagged "Reopened" (owner's rule, 2026-10-19).
alter table public.escalation_tickets
  add column if not exists reopen_count integer not null default 0,
  add column if not exists reopened_at timestamptz;
