-- =====================================================================
-- Christman Coordination Workspace — update 4 (version 0.4)
--   * meeting agenda and "before the meeting" checklist
--   * BIM Execution Plan (BEP): sections and files
--   * clash reports (Excel files shown in the app)
--   * only the admin edits meetings, the schedule, the BEP and clash reports
-- Run after update-3. Safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Meetings: agenda and preparation
-- ---------------------------------------------------------------------

alter table public.meetings add column if not exists agenda jsonb not null default '[]'::jsonb;  -- [{text, owner, minutes}]
alter table public.meetings add column if not exists prep   jsonb not null default '[]'::jsonb;  -- [{text, owner, due, done}]

-- Admin only from now on (everyone on the project can still read).
drop policy if exists meetings_write on public.meetings;
create policy meetings_write on public.meetings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists schedule_write on public.schedule_tasks;
create policy schedule_write on public.schedule_tasks for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- 2. BIM Execution Plan
-- ---------------------------------------------------------------------

create table if not exists public.bep_sections (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  title       text not null check (length(trim(title)) > 0),
  body        text not null default '',
  sort        int  not null default 0,
  updated_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists bep_sections_project_idx on public.bep_sections (project_id, sort);

create table if not exists public.bep_files (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects (id) on delete cascade,
  name         text not null check (length(trim(name)) > 0),
  description  text not null default '',
  category     text not null default 'Document',
  trade_id     uuid,                       -- null = for all trades
  path         text not null,              -- storage path in the 'files' bucket
  file_name    text not null,
  size_bytes   bigint not null default 0,
  uploaded_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  foreign key (trade_id, project_id) references public.project_trades (id, project_id) on delete set null (trade_id)
);
create index if not exists bep_files_project_idx on public.bep_files (project_id, created_at desc);

-- ---------------------------------------------------------------------
-- 3. Clash reports
-- ---------------------------------------------------------------------

create table if not exists public.clash_reports (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects (id) on delete cascade,
  title        text not null check (length(trim(title)) > 0),
  report_date  date not null default current_date,
  notes        text not null default '',
  path         text not null,
  file_name    text not null,
  size_bytes   bigint not null default 0,
  summary      jsonb not null default '{}'::jsonb,   -- {rows, statuses: {name: count}}
  uploaded_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists clash_reports_project_idx on public.clash_reports (project_id, report_date desc);

-- Stamp who changed what.
create or replace function public.stamp_editor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'bep_sections' then
    new.updated_by := coalesce(auth.uid(), new.updated_by);
    new.updated_at := now();
    if tg_op = 'UPDATE' then new.created_at := old.created_at; end if;
  else
    if tg_op = 'INSERT' then
      new.uploaded_by := coalesce(auth.uid(), new.uploaded_by);
      new.created_at := now();
    else
      new.uploaded_by := old.uploaded_by;
      new.created_at := old.created_at;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists bep_sections_stamp on public.bep_sections;
create trigger bep_sections_stamp before insert or update on public.bep_sections
  for each row execute function public.stamp_editor();
drop trigger if exists bep_files_stamp on public.bep_files;
create trigger bep_files_stamp before insert or update on public.bep_files
  for each row execute function public.stamp_editor();
drop trigger if exists clash_reports_stamp on public.clash_reports;
create trigger clash_reports_stamp before insert or update on public.clash_reports
  for each row execute function public.stamp_editor();

-- ---------------------------------------------------------------------
-- 4. Who can see / change (read: everyone on the project; change: admin)
-- ---------------------------------------------------------------------

alter table public.bep_sections  enable row level security;
alter table public.bep_files     enable row level security;
alter table public.clash_reports enable row level security;

drop policy if exists bep_sections_select on public.bep_sections;
create policy bep_sections_select on public.bep_sections for select to authenticated using (public.is_member(project_id));
drop policy if exists bep_sections_write on public.bep_sections;
create policy bep_sections_write on public.bep_sections for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists bep_files_select on public.bep_files;
create policy bep_files_select on public.bep_files for select to authenticated using (public.is_member(project_id));
drop policy if exists bep_files_write on public.bep_files;
create policy bep_files_write on public.bep_files for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists clash_reports_select on public.clash_reports;
create policy clash_reports_select on public.clash_reports for select to authenticated using (public.is_member(project_id));
drop policy if exists clash_reports_write on public.clash_reports;
create policy clash_reports_write on public.clash_reports for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on public.bep_sections, public.bep_files, public.clash_reports from anon;

-- ---------------------------------------------------------------------
-- 5. Live updates
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['bep_sections', 'bep_files', 'clash_reports'] loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', t);
      exception when duplicate_object then null;
      end;
    end loop;
  end if;
end $$;
