-- Staff (not the shared backup account) can edit an assignment in place
-- (assignee and kind) instead of deleting it and assigning again.
create policy "Staff edit evaluation_assignments" on public.evaluation_assignments
  for update to authenticated
  using ((select public.is_staff()) and not (select public.is_shared_account()))
  with check ((select public.is_staff()) and not (select public.is_shared_account()));
