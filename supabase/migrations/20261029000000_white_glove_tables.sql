-- White Glove section: tables that will receive its two Excel exports.
-- Nothing reads or writes the escalation tables; access reuses the escalation member and uploader lists.

-- One row per Excel uploaded to the White Glove section.
create table if not exists public.wg_uploads (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('review','aht')),   -- review = "All Team White Glove Review", aht = "WG AHT comparison"
  file_name text not null,
  row_count integer not null default 0,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  uploaded_at timestamptz not null default now()
);

-- "All Team White Glove Review" report: one row per ticket (the export repeats a ticket once per comment).
create table if not exists public.wg_review_tickets (
  ticket_number text primary key check (btrim(ticket_number) <> ''),
  ticket_owner text,
  mat_id text,
  account_name text,              -- "Name 1"
  subject text,
  opened_at timestamp,            -- "Date/Time Opened"
  opened_on date,                 -- "Opened Date"
  product_description text,
  asset_description text,
  serial_number text,
  status text,
  issue_type text,
  sub_issue_type text,
  ticket_type text,
  product_family text,
  last_upload_id bigint references public.wg_uploads(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- "Ticket Comments" of the review report, kept as written; a ticket can have several.
create table if not exists public.wg_review_comments (
  id bigint generated always as identity primary key,
  ticket_number text not null references public.wg_review_tickets(ticket_number) on delete cascade,
  comment text not null,
  comment_hash text generated always as (md5(comment)) stored,
  upload_id bigint references public.wg_uploads(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (ticket_number, comment_hash)
);

-- "WG AHT comparison": one sheet per month, two blocks per sheet (Team KPI and WG Team KPI).
-- Times are stored in seconds; the sheet's "Average" row is not stored (it is computed).
create table if not exists public.wg_aht (
  month date not null check (extract(day from month) = 1),  -- first day of the sheet's month
  team text not null check (team in ('team','wg')),          -- team = "Team KPI", wg = "WG Team KPI"
  agent text not null check (btrim(agent) <> ''),
  ahot_seconds numeric,
  wrap_up_seconds numeric,
  aht_seconds numeric,
  upload_id bigint references public.wg_uploads(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (month, team, agent)
);

create index if not exists wg_review_tickets_opened_on on public.wg_review_tickets (opened_on);
create index if not exists wg_review_comments_ticket on public.wg_review_comments (ticket_number);

do $$
declare t text;
begin
  foreach t in array array['wg_uploads','wg_review_tickets','wg_review_comments','wg_aht'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "Members read %1$s" on public.%1$I for select to authenticated using ((select public.is_escalation_member()))', t);
    execute format('create policy "Uploaders add %1$s" on public.%1$I for insert to authenticated with check ((select public.is_escalation_uploader()))', t);
    execute format('create policy "Uploaders edit %1$s" on public.%1$I for update to authenticated using ((select public.is_escalation_uploader())) with check ((select public.is_escalation_uploader()))', t);
    execute format('create policy "Uploaders delete %1$s" on public.%1$I for delete to authenticated using ((select public.is_escalation_uploader()))', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
