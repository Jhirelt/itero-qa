-- Members can be viewers: they see the whole report but only members with
-- can_upload may upload exports (insert/update tickets and uploads).
alter table public.escalation_members
  add column if not exists can_upload boolean not null default false;

-- The owner seeded in 20261015010000 keeps uploading.
update public.escalation_members set can_upload = true
where user_id in (select id from auth.users where email = 'j@admin.qa');

create or replace function public.is_escalation_uploader() returns boolean
  language sql stable security definer set search_path to 'public'
as $$ select exists (select 1 from escalation_members where user_id = auth.uid() and can_upload); $$;
revoke all on function public.is_escalation_uploader() from public, anon;
grant execute on function public.is_escalation_uploader() to authenticated;

alter policy "Members add escalation_uploads" on public.escalation_uploads
  with check ((select public.is_escalation_uploader()));
alter policy "Members edit escalation_uploads" on public.escalation_uploads
  using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()));
alter policy "Members add escalation_tickets" on public.escalation_tickets
  with check ((select public.is_escalation_uploader()));
alter policy "Members edit escalation_tickets" on public.escalation_tickets
  using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()));

