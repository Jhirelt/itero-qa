-- Escalations are for admins only: evaluators keep QA but cannot read or
-- change escalations or their updates.
-- Uses is_admin_id() (security definer): is_admin() reads profiles under RLS,
-- whose own policy calls is_admin() again, so it recurses for non-admins.
alter policy "Staff read escalations" on public.escalations
  using ((select public.is_admin_id((select auth.uid()))));
alter policy "Staff add escalations" on public.escalations
  with check ((select public.is_admin_id((select auth.uid()))));
alter policy "Staff edit escalations" on public.escalations
  using ((select public.is_admin_id((select auth.uid())))) with check ((select public.is_admin_id((select auth.uid()))));

alter policy "Staff read escalation_updates" on public.escalation_updates
  using ((select public.is_admin_id((select auth.uid()))));
alter policy "Staff add escalation_updates" on public.escalation_updates
  with check ((select public.is_admin_id((select auth.uid()))) and author_id = (select auth.uid()));
alter policy "Authors and admins delete escalation_updates" on public.escalation_updates
  using ((select public.is_admin_id((select auth.uid()))));

alter policy "Staff read escalations" on public.escalations rename to "Admins read escalations";
alter policy "Staff add escalations" on public.escalations rename to "Admins add escalations";
alter policy "Staff edit escalations" on public.escalations rename to "Admins edit escalations";
alter policy "Staff read escalation_updates" on public.escalation_updates rename to "Admins read escalation_updates";
alter policy "Staff add escalation_updates" on public.escalation_updates rename to "Admins add escalation_updates";
alter policy "Authors and admins delete escalation_updates" on public.escalation_updates rename to "Admins delete escalation_updates";

alter policy "Admins delete escalations" on public.escalations
  using ((select public.is_admin_id((select auth.uid()))));
