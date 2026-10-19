-- is_admin() read profiles as the caller, so the profiles read policy (which
-- calls is_admin()) re-entered itself: profile reads, logins, saves and
-- assignments hung for minutes. As a security definer it reads profiles
-- without RLS, like is_staff() and is_admin_id().
alter function public.is_admin() security definer;
alter function public.is_admin() set search_path = public;
