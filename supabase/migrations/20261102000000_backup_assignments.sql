-- Assignments can go to one person of a shared account (the SME backups):
-- assignee_id is the shared account, assignee_name the person.
alter table public.evaluation_assignments add column if not exists assignee_name text;

-- Taking an assignment from a shared account records which person took it.
-- A new two-argument version; the old one stays for pages still open.
create or replace function public.take_assignment(assignment uuid, as_name text)
  returns void
  language plpgsql
  security definer
  set search_path to 'public'
as $$
declare
  people text[];
begin
  if auth.uid() is null or not exists (select 1 from profiles where id = auth.uid()) then
    raise exception 'Sign in with a QA profile first.' using errcode = '42501';
  end if;
  select shared_people into people from profiles where id = auth.uid();
  update evaluation_assignments
     set assignee_id = auth.uid(),
         assignee_name = case when people is not null and as_name = any(people) then as_name end
   where id = assignment;
end;
$$;
revoke all on function public.take_assignment(uuid, text) from public, anon;
grant execute on function public.take_assignment(uuid, text) to authenticated;
