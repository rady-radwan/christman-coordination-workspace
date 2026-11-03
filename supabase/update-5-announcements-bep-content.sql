-- =====================================================================
-- Christman Coordination Workspace — update 5 (version 0.5)
--   * Announcements: the admin posts, everyone on the project is notified
--   * BEP sections can hold tables, checklists, note boxes and pictures
-- Run after update-4. Safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. BEP: rich section content (list of blocks). "body" keeps a plain-text copy.
-- ---------------------------------------------------------------------

alter table public.bep_sections add column if not exists content jsonb;

-- ---------------------------------------------------------------------
-- 2. Announcements
-- ---------------------------------------------------------------------

create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  title       text not null check (length(trim(title)) > 0),
  body        text not null default '',
  level       text not null default 'info' check (level in ('info', 'important', 'urgent')),
  pinned      boolean not null default false,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists announcements_project_idx on public.announcements (project_id, created_at desc);

create or replace function public.announcement_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.created_at := now();
  else
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists announcements_stamp on public.announcements;
create trigger announcements_stamp before insert or update on public.announcements
  for each row execute function public.announcement_stamp();

-- Everyone on the project hears about a new announcement.
create or replace function public.announcement_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  label text := case new.level when 'urgent' then 'Urgent: ' when 'important' then 'Important: ' else 'Announcement: ' end;
begin
  perform public.notify_users(
    (select coalesce(array_agg(user_id), '{}') from project_members where project_id = new.project_id),
    new.project_id, null, 'announcement', label || new.title, left(new.body, 200));
  return null;
end;
$$;

drop trigger if exists announcements_notify on public.announcements;
create trigger announcements_notify after insert on public.announcements
  for each row execute function public.announcement_notify();

alter table public.announcements enable row level security;

drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select to authenticated using (public.is_member(project_id));
drop policy if exists announcements_write on public.announcements;
create policy announcements_write on public.announcements for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on public.announcements from anon;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.announcements;
    exception when duplicate_object then null;
    end;
  end if;
end $$;
