-- Every evaluation needs a ticket ID.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'evaluations_ticket_required') then
    alter table public.evaluations add constraint evaluations_ticket_required check (ticket_id is not null and btrim(ticket_id) <> '');
  end if;
end $$;
