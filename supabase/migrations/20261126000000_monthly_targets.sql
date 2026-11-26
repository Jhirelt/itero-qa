-- Evaluations per agent per month can be set lower than 4 for a given month
-- (app_config.data.monthlyTargets = {"2026-11": 3, ...}; months not listed keep 4).
-- QA profiles (evaluators and admin) change it through save_shared_rubrics.

create or replace function public.monthly_eval_target(month_start date)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case when (data->'monthlyTargets'->>to_char(month_start, 'YYYY-MM')) ~ '^[1-4]$'
                then (data->'monthlyTargets'->>to_char(month_start, 'YYYY-MM'))::int end
      from public.app_config where id = 1
  ), 4);
$$;

create or replace function public.enforce_monthly_eval_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  month_start date := date_trunc('month', new.call_date)::date;
  existing int;
  target int;
begin
  if new.agent_id is null or new.call_date is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.agent_id = old.agent_id
     and date_trunc('month', new.call_date) = date_trunc('month', old.call_date) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('eval-limit:' || new.agent_id::text || ':' || month_start::text));
  target := public.monthly_eval_target(month_start);
  select count(*) into existing
    from public.evaluations
   where agent_id = new.agent_id
     and call_date >= month_start
     and call_date < (month_start + interval '1 month')
     and id is distinct from new.id;
  if existing >= target then
    raise exception 'MONTHLY_LIMIT: this agent already received their % evaluation% for %. Delete one of them to add a new one.',
      target, case when target = 1 then '' else 's' end, to_char(month_start, 'FMMonth YYYY')
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

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
   where key in ('items', 'order', 'focusPoints', 'criteriaSeed', 'taskActions', 'taskPeople', 'monthlyTargets');
  insert into public.app_config (id, data, updated_by, updated_at)
  values (1, allowed, auth.uid(), now())
  on conflict (id) do update
    set data = coalesce(public.app_config.data, '{}'::jsonb) || excluded.data,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;
