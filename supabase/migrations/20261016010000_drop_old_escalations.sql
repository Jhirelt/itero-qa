-- The hand-kept tracker (escalations + escalation_updates) is replaced by the
-- uploaded report. The owner asked to delete its data; a JSON copy was kept.
drop table if exists public.escalation_updates;
drop table if exists public.escalations;
