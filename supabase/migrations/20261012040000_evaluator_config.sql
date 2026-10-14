-- Evaluators (any QA profile) can now edit the rubrics and the focus point
-- list, add agents, and keep their own Evaluation page options.

-- 1) Shared rubric settings: staff may save only these keys of app_config.
create or replace function public.save_shared_rubrics(patch jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  allowed jsonb;
begin
  if not public.is_staff() then
    raise exception 'Only QA profiles can change the rubrics' using errcode = '42501';
  end if;
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into allowed
    from jsonb_each(coalesce(patch, '{}'::jsonb))
   where key in ('items', 'order', 'focusPoints', 'criteriaSeed');
  insert into public.app_config (id, data, updated_by, updated_at)
  values (1, allowed, auth.uid(), now())
  on conflict (id) do update
    set data = coalesce(public.app_config.data, '{}'::jsonb) || excluded.data,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;
revoke all on function public.save_shared_rubrics(jsonb) from public, anon;
grant execute on function public.save_shared_rubrics(jsonb) to authenticated;

-- 2) Any QA profile can add agents (editing and deleting stay admin-only).
do $$
declare p text;
begin
  select policyname into p from pg_policies
   where schemaname = 'public' and tablename = 'agents' and cmd = 'INSERT' limit 1;
  if p is not null then
    execute format('alter policy %I on public.agents with check (public.is_staff())', p);
  end if;
end $$;

-- 3) Per-person options (quick notes, focus points on the Evaluation page).
alter table public.profiles add column if not exists prefs jsonb not null default '{}'::jsonb;

create or replace function public.set_my_prefs(patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  update public.profiles
     set prefs = coalesce(prefs, '{}'::jsonb) || (
       select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
         from jsonb_each(coalesce(patch, '{}'::jsonb))
        where key in ('quickNotes', 'focusPoints') and jsonb_typeof(value) = 'boolean')
   where id = auth.uid()
  returning prefs into result;
  return result;
end;
$$;
revoke all on function public.set_my_prefs(jsonb) from public, anon;
grant execute on function public.set_my_prefs(jsonb) to authenticated;
