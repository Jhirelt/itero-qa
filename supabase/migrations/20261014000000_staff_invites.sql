-- Adding evaluators from the app: an admin writes the person's name and email
-- in Configuration. The first time that email signs in (or creates its
-- account), it gets a QA profile with that name and role.

create table if not exists public.staff_invites (
  email text primary key check (email = lower(btrim(email)) and email like '%@%'),
  display_name text not null check (btrim(display_name) <> ''),
  role text not null default 'evaluator' check (role in ('admin', 'evaluator')),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by uuid references auth.users(id) on delete set null
);
alter table public.staff_invites enable row level security;
create policy "Admins manage staff_invites" on public.staff_invites
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
grant select, insert, update, delete on public.staff_invites to authenticated;

-- Called after sign-in by an account with no QA profile. If an admin added
-- this account's email as staff, creates its profile and returns the role.
create or replace function public.claim_staff_invite() returns text
  language plpgsql security definer set search_path to 'public'
as $$
declare
  me uuid := auth.uid();
  mail text;
  inv staff_invites%rowtype;
begin
  if me is null then return null; end if;
  if exists (select 1 from profiles where id = me) then
    return (select role from profiles where id = me);
  end if;
  select email into mail from auth.users where id = me;
  if mail is null then return null; end if;
  select * into inv from staff_invites where email = lower(btrim(mail)) and claimed_at is null;
  if not found then return null; end if;
  insert into profiles (id, display_name, role) values (me, btrim(inv.display_name), inv.role)
    on conflict (id) do nothing;
  update staff_invites set claimed_at = now(), claimed_by = me where email = inv.email;
  return inv.role;
end;
$$;
revoke all on function public.claim_staff_invite() from public, anon;
grant execute on function public.claim_staff_invite() to authenticated;
