-- The shared backup account can't hand out tasks, a task given to the backup
-- account names the SME, and evaluators can copy a month's assignments
-- (which may replace open assignments other people made).

create or replace function public.is_shared_account() returns boolean
  language sql stable security definer set search_path to 'public'
as $$
  select exists (select 1 from profiles where id = auth.uid() and shared_people is not null);
$$;
revoke all on function public.is_shared_account() from public, anon;
grant execute on function public.is_shared_account() to authenticated;

create policy "Shared accounts cannot add tasks" on public.tasks
  as restrictive for insert to authenticated
  with check (not (select public.is_shared_account()));

-- Same as before, plus: a shared account can't change who a task is for, and
-- switching the SME on a backup task notifies again.
create or replace function public.tasks_track()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  by_admin boolean := public.is_admin();
begin
  new.updated_at := now();
  if tg_op = 'INSERT' and by_admin then
    new.created_by := null;
  end if;
  if tg_op = 'UPDATE' and public.is_shared_account()
     and (new.responsible_id is distinct from old.responsible_id or new.responsible_name is distinct from old.responsible_name) then
    raise exception 'The backup account can''t assign tasks.' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' or new.responsible_id is distinct from old.responsible_id or new.responsible_name is distinct from old.responsible_name then
    if by_admin then
      new.assigned_by := null;
      new.seen_by_assignee := true;
    else
      new.assigned_by := auth.uid();
      new.seen_by_assignee := coalesce(new.responsible_id is null or new.responsible_id = auth.uid(), false);
    end if;
  end if;
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
    new.completed_at := coalesce(new.completed_at, now());
    new.completed_by := case when by_admin then null else coalesce(auth.uid(), new.completed_by) end;
  elsif new.status = 'pending' then
    new.completed_at := null;
    new.completed_by := null;
  end if;
  return new;
end;
$function$;

alter policy "Assigner, assignee or admin can remove evaluation_assignments" on public.evaluation_assignments
  using (
    (assigned_by = (select auth.uid())) or (assignee_id = (select auth.uid())) or (select public.is_admin())
    or ((select public.is_staff()) and not (select public.is_shared_account()))
  );
