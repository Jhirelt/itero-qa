-- iTero Support (Report tab): each issue category is Regular or Technical, and the Salesforce cases export uploaded there.
create table if not exists public.support_issue_categories (
  category text primary key check (btrim(category) <> ''),
  kind text not null check (kind in ('Regular','Technical')),
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now()
);
alter table public.support_issue_categories enable row level security;
create policy "Members read support_issue_categories" on public.support_issue_categories
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Uploaders add support_issue_categories" on public.support_issue_categories
  for insert to authenticated with check ((select public.is_escalation_uploader()));
create policy "Uploaders edit support_issue_categories" on public.support_issue_categories
  for update to authenticated using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()));
create policy "Uploaders delete support_issue_categories" on public.support_issue_categories
  for delete to authenticated using ((select public.is_escalation_uploader()));
grant select, insert, update, delete on public.support_issue_categories to authenticated;

insert into public.support_issue_categories (category, kind) values
  ('Company Relation','Regular'), ('Contact information','Regular'), ('Other','Regular'), ('Wand disconnections','Technical'),
  ('How to','Regular'), ('Gray Screen','Technical'), ('Wand doesn''t work','Technical'), ('Inquiry','Regular'),
  ('Password reset','Regular'), ('Configuration','Regular'), ('Windows','Regular'), ('SW Upgrade / Update','Technical'),
  ('SW crashed','Technical'), ('Invisalign Bridging','Regular'), ('Upgrade/Update','Technical'), ('iTero Needs To Be Closed Error Message','Technical'),
  ('Training','Regular'), ('Fulfillment','Regular'), ('RX','Regular'), ('Slowness','Technical'),
  ('Activation','Regular'), ('Refund','Regular'), ('Digital model','Regular'), ('Sales/Marketing Program','Regular'),
  ('Onboarding','Regular'), ('Subscription billing','Technical'), ('Crash','Technical'), ('SW Feature','Technical'),
  ('Lumina SW Feature','Technical'), ('iTero 360','Regular'), ('Stitching issues','Technical'), ('Re-Registration','Technical'),
  ('Resto','Technical'), ('Post Processing','Technical'), ('Labels','Regular'), ('Relocation processing','Regular'),
  ('Scanning Quality Issues','Technical'), ('Add a Lab','Regular'), ('Internal user','Regular'), ('Installation','Regular'),
  ('Lumina SW Upgrade failure','Technical'), ('IF box Failure','Technical'), ('Online Store','Regular'), ('Cancel','Regular'),
  ('PC RMA','Technical'), ('Case Status / iTero Flow','Regular'), ('Missing Data','Technical'), ('Customer satisfaction','Regular'),
  ('Missing ''IOSim Pro'' button','Technical'), ('Cradle','Technical'), ('Power supply Issues','Technical'), ('Travel Case','Regular'),
  ('Resale processing','Regular'), ('Simulation Failed','Technical'), ('User Issue','Technical'), ('Slow performances','Technical'),
  ('Scan Report','Technical'), ('Networking','Technical'), ('itero.com','Technical'), ('Battery issue','Technical'),
  ('Application Support','Technical'), ('Lens - Physical Damage','Regular'), ('Lab purchase','Regular'), ('Merge','Regular'),
  ('Wand LED ring','Technical'), ('Package - Damaged','Technical'), ('Package - Missing','Technical'), ('Technical Issue','Technical')
on conflict (category) do update set kind = excluded.kind;

-- The latest Salesforce cases export uploaded in iTero Support; a new upload replaces the rows of the previous one.
create table if not exists public.support_case_uploads (
  id uuid primary key default gen_random_uuid(),
  file_name text,
  row_count int not null default 0,
  case_count int not null default 0,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  uploaded_at timestamptz not null default now()
);
create table if not exists public.support_cases (
  id bigint generated always as identity primary key,
  upload_id uuid not null references public.support_case_uploads(id) on delete cascade,
  case_number text,
  opened_on date,
  issue_category text,
  cases int not null default 1 check (cases >= 0)
);
create index if not exists support_cases_upload_idx on public.support_cases(upload_id);
alter table public.support_case_uploads enable row level security;
alter table public.support_cases enable row level security;
create policy "Members read support_case_uploads" on public.support_case_uploads
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Uploaders add support_case_uploads" on public.support_case_uploads
  for insert to authenticated with check ((select public.is_escalation_uploader()));
create policy "Uploaders edit support_case_uploads" on public.support_case_uploads
  for update to authenticated using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()));
create policy "Uploaders delete support_case_uploads" on public.support_case_uploads
  for delete to authenticated using ((select public.is_escalation_uploader()));
create policy "Members read support_cases" on public.support_cases
  for select to authenticated using ((select public.is_escalation_member()));
create policy "Uploaders add support_cases" on public.support_cases
  for insert to authenticated with check ((select public.is_escalation_uploader()));
create policy "Uploaders delete support_cases" on public.support_cases
  for delete to authenticated using ((select public.is_escalation_uploader()));
grant select, insert, update, delete on public.support_case_uploads to authenticated;
grant select, insert, delete on public.support_cases to authenticated;
