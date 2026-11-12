-- Escalations rights: admin (everything, manages rights), uploader (uploads and edits ticket details), viewer (read only).
alter table public.escalation_members
  add column if not exists role text not null default 'viewer'
  check (role in ('admin','uploader','viewer'));

update public.escalation_members set role = case when can_upload then 'admin' else 'viewer' end;

-- can_upload stays for the policies and the page, and always follows the role.
create or replace function public.escalation_members_sync()
returns trigger language plpgsql set search_path = public as $$
begin
  new.can_upload := new.role in ('admin','uploader');
  return new;
end $$;

drop trigger if exists escalation_members_sync on public.escalation_members;
create trigger escalation_members_sync before insert or update on public.escalation_members
  for each row execute function public.escalation_members_sync();

create or replace function public.is_escalation_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from escalation_members where user_id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_escalation_uploader()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from escalation_members where user_id = auth.uid() and role in ('admin','uploader'));
$$;

-- Every account that can sign in, with its rights here ('none' = no access). Admins only.
create or replace function public.escalation_admin_users()
returns table(user_id uuid, email text, display_name text, role text, last_sign_in timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_escalation_admin() then
    raise exception 'Only admins can manage rights' using errcode = '42501';
  end if;
  return query
    select u.id, u.email::text,
           coalesce(m.display_name, nullif(u.raw_user_meta_data->>'display_name',''), nullif(u.raw_user_meta_data->>'full_name',''), split_part(u.email,'@',1)),
           coalesce(m.role, 'none'), u.last_sign_in_at
    from auth.users u left join escalation_members m on m.user_id = u.id
    order by (m.role is null), lower(coalesce(m.display_name, u.email));
end $$;

-- Give, change or remove (new_role 'none') someone's rights. Admins only; an admin cannot lower their own rights.
create or replace function public.escalation_set_role(target uuid, new_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_escalation_admin() then
    raise exception 'Only admins can manage rights' using errcode = '42501';
  end if;
  if new_role not in ('admin','uploader','viewer','none') then
    raise exception 'Unknown role %', new_role using errcode = '22023';
  end if;
  if target = auth.uid() and new_role <> 'admin' then
    raise exception 'You cannot lower your own rights' using errcode = '42501';
  end if;
  if new_role = 'none' then
    delete from escalation_members where user_id = target;
  else
    insert into escalation_members (user_id, display_name, role)
    select u.id, coalesce(nullif(u.raw_user_meta_data->>'display_name',''), split_part(u.email,'@',1)), new_role
    from auth.users u where u.id = target
    on conflict (user_id) do update set role = excluded.role;
    if not found then raise exception 'Account not found' using errcode = '22023'; end if;
  end if;
end $$;

-- Change how someone's name shows on the page. Admins only.
create or replace function public.escalation_set_name(target uuid, new_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_escalation_admin() then
    raise exception 'Only admins can manage rights' using errcode = '42501';
  end if;
  if coalesce(btrim(new_name),'') = '' then raise exception 'Name cannot be empty' using errcode = '22023'; end if;
  update escalation_members set display_name = btrim(new_name) where user_id = target;
end $$;

revoke all on function public.escalation_admin_users() from public, anon;
revoke all on function public.escalation_set_role(uuid, text) from public, anon;
revoke all on function public.escalation_set_name(uuid, text) from public, anon;
revoke all on function public.is_escalation_admin() from anon;
grant execute on function public.escalation_admin_users() to authenticated;
grant execute on function public.escalation_set_role(uuid, text) to authenticated;
grant execute on function public.escalation_set_name(uuid, text) to authenticated;
grant execute on function public.is_escalation_admin() to authenticated;
