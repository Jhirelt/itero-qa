-- Agent portal: agents can sign in and see only their own evaluations, when an
-- admin turns it on in Configuration (app_config.data.features.agentPortal).
-- Agents have no QA profile; their account is linked to an agent row instead.

alter table public.agents add column if not exists login_email text;
create unique index if not exists agents_login_email_key on public.agents (lower(login_email)) where login_email is not null;

create table if not exists public.agent_logins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  agent_id uuid not null references public.agents(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.agent_logins enable row level security;
create policy "Agent or admin can read agent_logins" on public.agent_logins
  for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
grant select on public.agent_logins to authenticated;

-- QA staff = anyone with a profile (admin or evaluator).
create or replace function public.is_staff() returns boolean
  language sql stable security definer set search_path to 'public'
as $$ select exists (select 1 from profiles where id = auth.uid()); $$;

create or replace function public.agent_portal_on() returns boolean
  language sql stable security definer set search_path to 'public'
as $$ select coalesce((select (data->'features'->>'agentPortal')::boolean from app_config where id = 1), false); $$;

-- The agent this signed-in account belongs to, while the portal is on.
create or replace function public.my_agent_id() returns uuid
  language sql stable security definer set search_path to 'public'
as $$ select l.agent_id from agent_logins l where l.user_id = auth.uid() and agent_portal_on(); $$;

-- Called after sign-in by an account with no QA profile: links it to the agent
-- whose login email matches the account's email. Returns the agent id or null.
create or replace function public.claim_agent_login() returns uuid
  language plpgsql security definer set search_path to 'public'
as $$
declare
  me uuid := auth.uid();
  mail text;
  found uuid;
begin
  if me is null or not agent_portal_on() or exists (select 1 from profiles where id = me) then
    return null;
  end if;
  select email into mail from auth.users where id = me;
  if mail is null then return null; end if;
  select id into found from agents where lower(login_email) = lower(mail);
  if found is null then return null; end if;
  insert into agent_logins (user_id, agent_id) values (me, found)
    on conflict (user_id) do update set agent_id = excluded.agent_id;
  return found;
end;
$$;
grant execute on function public.is_staff(), public.agent_portal_on(), public.my_agent_id(), public.claim_agent_login() to authenticated;

-- Reads: staff see everything; an agent sees only their own rows.
alter policy "Authenticated can read evaluations" on public.evaluations
  using ((select public.is_staff()) or agent_id = (select public.my_agent_id()));
alter policy "Authenticated can read evaluation_sections" on public.evaluation_sections
  using ((select public.is_staff()) or exists (select 1 from public.evaluations e where e.id = evaluation_sections.evaluation_id and e.agent_id = (select public.my_agent_id())));
alter policy "Authenticated can read evaluation_deductions" on public.evaluation_deductions
  using ((select public.is_staff()) or exists (select 1 from public.evaluations e where e.id = evaluation_deductions.evaluation_id and e.agent_id = (select public.my_agent_id())));
alter policy "Authenticated can read agents" on public.agents
  using ((select public.is_staff()) or id = (select public.my_agent_id()));
alter policy "Authenticated users can read profiles" on public.profiles
  using ((select public.is_staff()));
alter policy "Authenticated can read evaluation_assignments" on public.evaluation_assignments
  using ((select public.is_staff()));
alter policy "Authenticated can read evaluation_presence" on public.evaluation_presence
  using ((select public.is_staff()));

-- Writes: only QA staff can create evaluations, assignments or presence rows.
alter policy "Authenticated can create evaluations" on public.evaluations
  with check ((select public.is_staff()));
alter policy "Authenticated can create evaluation_sections" on public.evaluation_sections
  with check ((select public.is_staff()));
alter policy "Authenticated can create evaluation_deductions" on public.evaluation_deductions
  with check ((select public.is_staff()));
alter policy "Authenticated can create own evaluation_assignments" on public.evaluation_assignments
  with check (assigned_by = (select auth.uid()) and (select public.is_staff()));
alter policy "Evaluator can add own evaluation_presence" on public.evaluation_presence
  with check (user_id = (select auth.uid()) and (select public.is_staff()));
