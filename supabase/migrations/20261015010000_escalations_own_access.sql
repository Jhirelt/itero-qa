-- Escalations are separate from QA Evaluation: they only share the site,
-- the Supabase project and sign-in accounts. Access is its own list,
-- escalation_members, not QA's profiles or roles; adding someone to QA
-- (admin or evaluator) gives them nothing here.

create table if not exists public.escalation_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (btrim(display_name) <> ''),
  added_at timestamptz not null default now()
);
alter table public.escalation_members enable row level security;
-- Members see their own row (for the name on the page). The list is managed
-- from the Supabase dashboard / SQL only; nothing in the app can change it.
create policy "Members read own escalation_members row" on public.escalation_members
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.escalation_members to authenticated;

-- Security definer so policies can call it without going through RLS.
create or replace function public.is_escalation_member() returns boolean
  language sql stable security definer set search_path to 'public'
as $$ select exists (select 1 from escalation_members where user_id = auth.uid()); $$;
revoke all on function public.is_escalation_member() from public, anon;
grant execute on function public.is_escalation_member() to authenticated;

-- First member: the QA admin account that owns both apps.
insert into public.escalation_members (user_id, display_name)
select id, 'Jhirelt' from auth.users where email = 'j@admin.qa'
on conflict (user_id) do nothing;

alter policy "Staff read escalations" on public.escalations
  using ((select public.is_escalation_member()));
alter policy "Staff add escalations" on public.escalations
  with check ((select public.is_escalation_member()));
alter policy "Staff edit escalations" on public.escalations
  using ((select public.is_escalation_member())) with check ((select public.is_escalation_member()));
alter policy "Admins delete escalations" on public.escalations
  using ((select public.is_escalation_member()));
alter policy "Staff read escalation_updates" on public.escalation_updates
  using ((select public.is_escalation_member()));
alter policy "Staff add escalation_updates" on public.escalation_updates
  with check ((select public.is_escalation_member()) and author_id = (select auth.uid()));
alter policy "Authors and admins delete escalation_updates" on public.escalation_updates
  using ((select public.is_escalation_member()));

alter policy "Staff read escalations" on public.escalations rename to "Members read escalations";
alter policy "Staff add escalations" on public.escalations rename to "Members add escalations";
alter policy "Staff edit escalations" on public.escalations rename to "Members edit escalations";
alter policy "Admins delete escalations" on public.escalations rename to "Members delete escalations";
alter policy "Staff read escalation_updates" on public.escalation_updates rename to "Members read escalation_updates";
alter policy "Staff add escalation_updates" on public.escalation_updates rename to "Members add escalation_updates";
alter policy "Authors and admins delete escalation_updates" on public.escalation_updates rename to "Members delete escalation_updates";
