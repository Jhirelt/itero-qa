-- Shared evaluator account (backup for the SMEs). The account lists the people
-- who use it; at sign-in the app asks which of them is evaluating, and their
-- evaluations are saved under that person's name.

alter table public.staff_invites add column if not exists shared_people text[];
alter table public.profiles add column if not exists shared_people text[];

-- Same as before, plus the people list goes from the invite to the profile.
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
  insert into profiles (id, display_name, role, shared_people) values (me, btrim(inv.display_name), inv.role, inv.shared_people)
    on conflict (id) do nothing;
  update staff_invites set claimed_at = now(), claimed_by = me where email = inv.email;
  return inv.role;
end;
$$;
revoke all on function public.claim_staff_invite() from public, anon;
grant execute on function public.claim_staff_invite() to authenticated;

-- A shared account keeps the name the app sent when it is one of its people;
-- every other evaluator still gets the name from their profile.
create or replace function public.evaluations_hide_admin()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  prof_name text;
  people text[];
begin
  if public.is_admin() then
    if tg_op = 'INSERT' then
      new.evaluator_name := 'QA';
    else
      new.updated_at := old.updated_at;
    end if;
  elsif tg_op = 'INSERT' then
    select nullif(btrim(display_name), ''), shared_people into prof_name, people from profiles where id = auth.uid();
    if people is not null and new.evaluator_name = any(people) then
      return new;
    end if;
    new.evaluator_name := coalesce(prof_name, new.evaluator_name);
  end if;
  return new;
end;
$$;
