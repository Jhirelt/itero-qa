-- At most 4 evaluations per agent per calendar month (by call date).
-- To add another one, an existing evaluation for that month must be deleted first.
create or replace function public.enforce_monthly_eval_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  month_start date := date_trunc('month', new.call_date)::date;
  existing int;
begin
  if new.agent_id is null or new.call_date is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.agent_id = old.agent_id
     and date_trunc('month', new.call_date) = date_trunc('month', old.call_date) then
    return new;
  end if;
  -- Two evaluators saving the same agent at once take turns here.
  perform pg_advisory_xact_lock(hashtext('eval-limit:' || new.agent_id::text || ':' || month_start::text));
  select count(*) into existing
    from public.evaluations
   where agent_id = new.agent_id
     and call_date >= month_start
     and call_date < (month_start + interval '1 month')
     and id is distinct from new.id;
  if existing >= 4 then
    raise exception 'MONTHLY_LIMIT: this agent already received their 4 evaluations for %. Delete one of them to add a new one.',
      to_char(month_start, 'FMMonth YYYY')
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'evaluations_monthly_limit') then
    create trigger evaluations_monthly_limit
      before insert or update of agent_id, call_date on public.evaluations
      for each row execute function public.enforce_monthly_eval_limit();
  end if;
end $$;
