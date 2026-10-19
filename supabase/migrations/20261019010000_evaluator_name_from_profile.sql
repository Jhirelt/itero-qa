-- When an evaluator's profile could not be read at sign-in, the app saved their
-- email as the evaluator name. Evaluations now always take the evaluator's name
-- from their profile, and the ones saved with an email get the name back.
create or replace function public.evaluations_hide_admin()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.is_admin() then
    if tg_op = 'INSERT' then
      new.evaluator_name := 'QA';
    else
      new.updated_at := old.updated_at;
    end if;
  elsif tg_op = 'INSERT' then
    new.evaluator_name := coalesce(
      (select nullif(btrim(display_name), '') from profiles where id = auth.uid()),
      new.evaluator_name);
  end if;
  return new;
end;
$$;

update public.evaluations e
   set evaluator_name = p.display_name
  from public.profiles p
 where p.id = e.evaluator_id
   and p.role <> 'admin'
   and e.evaluator_name like '%@%';
