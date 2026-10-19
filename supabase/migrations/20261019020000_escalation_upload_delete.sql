-- Uploaders can delete an upload and the tickets whose current data came from it.
create policy "Uploaders delete escalation_uploads" on public.escalation_uploads
  for delete to authenticated using ((select public.is_escalation_uploader()));
create policy "Uploaders delete escalation_tickets" on public.escalation_tickets
  for delete to authenticated using ((select public.is_escalation_uploader()));
grant delete on public.escalation_uploads, public.escalation_tickets to authenticated;
