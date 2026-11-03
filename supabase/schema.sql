-- =====================================================================
-- Christman Coordination Workspace — database setup (Stage 1)
--
-- Run once on a NEW Supabase project:
--   Supabase dashboard > SQL Editor > New query > paste this whole file > Run.
--
-- What it creates:
--   people (profiles), projects, trades, item types, project team,
--   coordination items with automatic numbering (NMC-CL-001),
--   discussion, history log, in-app notifications and invitations.
-- All permission rules live here, so the app cannot get around them.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  name        text not null default '',
  email       text not null default '',
  company     text not null default '',
  phone       text not null default '',
  is_admin    boolean not null default false,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'removed')),
  created_at  timestamptz not null default now()
);
create unique index if not exists profiles_email_idx on public.profiles (lower(email));

create table if not exists public.projects (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (length(trim(name)) > 0),
  code               text not null check (code ~ '^[A-Z0-9]{1,8}$'),
  location           text not null default '',
  buildings          text[] not null default '{}',
  levels             text[] not null default '{}',
  zones              text[] not null default '{}',
  default_due_days   int  not null default 3 check (default_due_days between 0 and 60),
  model_due_weekday  int  not null default 5 check (model_due_weekday between 1 and 7),
  archived           boolean not null default false,
  created_at         timestamptz not null default now()
);
create unique index if not exists projects_code_idx on public.projects (code);

create table if not exists public.project_trades (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  code        text not null check (code ~ '^[A-Z0-9]{1,6}$'),
  company     text not null default '',
  sort        int  not null default 0,
  created_at  timestamptz not null default now(),
  unique (project_id, code),
  unique (id, project_id)
);

create table if not exists public.item_types (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  code        text not null check (code ~ '^[A-Z0-9]{1,4}$'),
  sort        int  not null default 0,
  active      boolean not null default true,
  unique (project_id, code),
  unique (id, project_id)
);

create table if not exists public.project_members (
  project_id  uuid not null references public.projects (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        text not null check (role in ('coordinator', 'trade_lead', 'trade_member', 'viewer')),
  trade_id    uuid,
  added_at    timestamptz not null default now(),
  primary key (project_id, user_id),
  foreign key (trade_id, project_id) references public.project_trades (id, project_id),
  check (role not in ('trade_lead', 'trade_member') or trade_id is not null)
);
create index if not exists project_members_user_idx on public.project_members (user_id);

create table if not exists public.items (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects (id) on delete cascade,
  type_id       uuid not null,
  serial        int  not null default 0,
  number        text not null default '',
  title         text not null check (length(trim(title)) > 0),
  description   text not null default '',
  priority      text not null default 'medium'
                check (priority in ('urgent', 'critical', 'high', 'medium', 'low')),
  status        text not null default 'open'
                check (status in ('open', 'in_review', 'response_submitted', 'model_updated', 'closed', 'on_hold', 'void')),
  building      text not null default '',
  level         text not null default '',
  zone          text not null default '',
  grid          text not null default '',
  clash_test    text not null default '',
  clash_id      text not null default '',
  viewpoint     text not null default '',
  revit_ids     text not null default '',
  sheet         text not null default '',
  trade_ids     uuid[] not null default '{}',
  bic_trade_id  uuid,               -- null = ball is with the Christman coordinator
  bic_since     timestamptz not null default now(),
  due_date      date,
  needs_rfi     boolean not null default false,
  rfi_number    text not null default '',
  import_key    text,               -- used by the clash import (Stage 3) to skip duplicates
  created_by    uuid not null references public.profiles (id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  closed_at     timestamptz,
  closed_by     uuid references public.profiles (id),
  foreign key (type_id, project_id) references public.item_types (id, project_id),
  foreign key (bic_trade_id, project_id) references public.project_trades (id, project_id)
);
create unique index if not exists items_number_idx on public.items (project_id, number);
create unique index if not exists items_import_key_idx on public.items (project_id, import_key) where import_key is not null;
create index if not exists items_project_status_idx on public.items (project_id, status);

create table if not exists public.item_counters (
  project_id   uuid not null references public.projects (id) on delete cascade,
  type_id      uuid not null references public.item_types (id) on delete cascade,
  last_serial  int  not null default 0,
  primary key (project_id, type_id)
);

create table if not exists public.item_comments (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null references public.items (id) on delete cascade,
  author_id    uuid not null references public.profiles (id),
  body         text not null default '',
  attachments  jsonb not null default '[]'::jsonb,   -- photos / voice / files (Stage 2)
  created_at   timestamptz not null default now(),
  edited_at    timestamptz
);
create index if not exists item_comments_item_idx on public.item_comments (item_id, created_at);

create table if not exists public.item_events (
  id          bigint generated always as identity primary key,
  item_id     uuid not null references public.items (id) on delete cascade,
  actor_id    uuid references public.profiles (id) on delete set null,
  kind        text not null,      -- created, status, ball, priority, due, rfi, edited
  from_value  text not null default '',
  to_value    text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists item_events_item_idx on public.item_events (item_id, created_at);

create table if not exists public.notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  project_id  uuid references public.projects (id) on delete cascade,
  item_id     uuid references public.items (id) on delete cascade,
  kind        text not null,      -- new_item, ball, response, closed, comment, signup, suggestion
  title       text not null,
  body        text not null default '',
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

create table if not exists public.invites (
  id            uuid primary key default gen_random_uuid(),
  email         text not null check (email like '%@%'),
  name          text not null default '',
  company       text not null default '',
  project_id    uuid not null references public.projects (id) on delete cascade,
  role          text not null check (role in ('coordinator', 'trade_lead', 'trade_member', 'viewer')),
  trade_id      uuid,
  status        text not null default 'approved' check (status in ('suggested', 'approved', 'rejected', 'used')),
  suggested_by  uuid references public.profiles (id) on delete set null,
  decided_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  decided_at    timestamptz,
  foreign key (trade_id, project_id) references public.project_trades (id, project_id) on delete cascade,
  check (role not in ('trade_lead', 'trade_member') or trade_id is not null)
);
create index if not exists invites_email_idx on public.invites (lower(email));

-- ---------------------------------------------------------------------
-- 2. Who-am-I helpers (security definer, so policies don't loop)
-- ---------------------------------------------------------------------

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved');
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved' and is_admin);
$$;

-- 'admin', 'coordinator', 'trade_lead', 'trade_member', 'viewer' or null (not on the project).
create or replace function public.member_role(pid uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.is_admin() then 'admin'
    else (select m.role from project_members m join profiles p on p.id = m.user_id
          where m.project_id = pid and m.user_id = auth.uid() and p.status = 'approved')
  end;
$$;

create or replace function public.is_member(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.member_role(pid) is not null;
$$;

create or replace function public.is_coord(pid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.member_role(pid) in ('admin', 'coordinator'), false);
$$;

create or replace function public.my_trade(pid uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select trade_id from project_members where project_id = pid and user_id = auth.uid();
$$;

create or replace function public.can_see_item(iid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from items i where i.id = iid and public.is_member(i.project_id));
$$;

create or replace function public.shares_project(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from project_members a join project_members b on a.project_id = b.project_id
    where a.user_id = auth.uid() and b.user_id = uid);
$$;

-- Display name for a trade (null = the coordinator).
create or replace function public.trade_label(tid uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select name || case when company <> '' then ' · ' || company else '' end
                   from project_trades where id = tid), 'Christman VDC');
$$;

-- ---------------------------------------------------------------------
-- 3. Notification helpers
-- ---------------------------------------------------------------------

create or replace function public.notify_users(uids uuid[], pid uuid, iid uuid, k text, t text, b text)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, project_id, item_id, kind, title, body)
  select distinct u, pid, iid, k, t, b
  from unnest(uids) u
  join profiles p on p.id = u and p.status = 'approved'
  where u is distinct from auth.uid();
$$;

create or replace function public.trade_people(pid uuid, tids uuid[]) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(user_id), '{}') from project_members
  where project_id = pid and trade_id = any(tids) and role in ('trade_lead', 'trade_member');
$$;

create or replace function public.coordinators(pid uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(user_id), '{}') from project_members
  where project_id = pid and role = 'coordinator';
$$;

create or replace function public.admins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(id), '{}') from profiles where is_admin and status = 'approved';
$$;

-- ---------------------------------------------------------------------
-- 4. Sign-up, approval and invitations
-- ---------------------------------------------------------------------

-- New account -> profile. The very first account becomes the approved admin.
-- Someone with an approved invitation is approved and added to the project
-- automatically. Everyone else waits for the admin.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  first_user boolean;
  inv record;
  invited boolean;
begin
  select not exists (select 1 from profiles) into first_user;
  select exists (select 1 from invites where lower(email) = lower(new.email) and status = 'approved') into invited;

  insert into profiles (id, name, email, company, is_admin, status)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''),
             (select name from invites where lower(email) = lower(new.email) and name <> '' order by created_at desc limit 1),
             split_part(new.email, '@', 1)),
    lower(new.email),
    coalesce(nullif(new.raw_user_meta_data ->> 'company', ''),
             (select company from invites where lower(email) = lower(new.email) and company <> '' order by created_at desc limit 1),
             ''),
    first_user,
    case when first_user or invited then 'approved' else 'pending' end
  );

  for inv in select * from invites where lower(email) = lower(new.email) and status = 'approved' loop
    insert into project_members (project_id, user_id, role, trade_id)
    values (inv.project_id, new.id, inv.role, inv.trade_id)
    on conflict (project_id, user_id) do update set role = excluded.role, trade_id = excluded.trade_id;
    update invites set status = 'used', decided_at = coalesce(decided_at, now()) where id = inv.id;
  end loop;

  if not first_user and not invited then
    perform notify_users(admins(), null, null, 'signup', 'New sign-up waiting for approval',
      coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), new.email) ||
      coalesce(' · ' || nullif(new.raw_user_meta_data ->> 'company', ''), ''));
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only the admin changes roles, approval or email; people may edit their own name, company, phone.
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin()
     and (new.is_admin is distinct from old.is_admin or new.status is distinct from old.status
          or new.email is distinct from old.email) then
    raise exception 'Only the admin can change roles or approval.';
  end if;
  if auth.uid() is not null and new.id = auth.uid() and old.is_admin and not new.is_admin
     and not exists (select 1 from profiles where is_admin and status = 'approved' and id <> new.id) then
    raise exception 'You are the only admin. Make someone else admin first.';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Invitations: the admin adds people directly; a trade lead may only SUGGEST
-- a new member for their own trade, which the admin then approves.
create or replace function public.guard_invite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.email := lower(trim(new.email));
  if auth.uid() is null or public.is_admin() then
    if tg_op = 'INSERT' and new.status = 'approved' then
      new.decided_by := coalesce(new.decided_by, auth.uid());
      new.decided_at := now();
    end if;
    if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('approved', 'rejected') then
      new.decided_by := auth.uid();
      new.decided_at := now();
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' and public.member_role(new.project_id) = 'trade_lead'
     and new.status = 'suggested' and new.role = 'trade_member'
     and new.trade_id = public.my_trade(new.project_id) then
    new.suggested_by := auth.uid();
    new.decided_by := null;
    new.decided_at := null;
    return new;
  end if;
  raise exception 'Trade leads can only suggest new members for their own trade.';
end;
$$;

drop trigger if exists invites_guard on public.invites;
create trigger invites_guard before insert or update on public.invites
  for each row execute function public.guard_invite();

-- When an invitation is approved and that person already has an account,
-- add them to the project right away.
create or replace function public.apply_invite() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
  pname text;
begin
  if new.status = 'suggested' and (tg_op = 'INSERT' or old.status is distinct from 'suggested') then
    select name into pname from projects where id = new.project_id;
    perform notify_users(admins(), new.project_id, null, 'suggestion', 'New team member suggested',
      coalesce(nullif(new.name, ''), new.email) || ' · ' || trade_label(new.trade_id) || ' · ' || pname);
  end if;
  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    select id into uid from profiles where lower(email) = new.email;
    if uid is not null then
      insert into project_members (project_id, user_id, role, trade_id)
      values (new.project_id, uid, new.role, new.trade_id)
      on conflict (project_id, user_id) do update set role = excluded.role, trade_id = excluded.trade_id;
      update profiles set status = 'approved' where id = uid and status = 'pending';
      update invites set status = 'used' where id = new.id;
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists invites_apply on public.invites;
create trigger invites_apply after insert or update on public.invites
  for each row execute function public.apply_invite();

-- ---------------------------------------------------------------------
-- 5. Projects: defaults for a new project
-- ---------------------------------------------------------------------

create or replace function public.project_defaults() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.code := upper(trim(new.code));
  return new;
end;
$$;

drop trigger if exists projects_defaults on public.projects;
create trigger projects_defaults before insert or update on public.projects
  for each row execute function public.project_defaults();

-- New project: standard item types, standard trades, and its creator as coordinator.
create or replace function public.project_seed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into item_types (project_id, name, code, sort) values
    (new.id, 'Clash', 'CL', 1),
    (new.id, 'Routing / Space Request', 'RT', 2),
    (new.id, 'Design Question', 'DQ', 3),
    (new.id, 'Model Update Request', 'MU', 4),
    (new.id, 'Sleeve / Penetration', 'SL', 5),
    (new.id, 'Hanger / Support', 'HS', 6),
    (new.id, 'Access / Clearance', 'AC', 7),
    (new.id, 'Constructability', 'CN', 8),
    (new.id, 'General', 'GN', 9);
  insert into project_trades (project_id, name, code, sort) values
    (new.id, 'Mechanical', 'MECH', 1),
    (new.id, 'Plumbing', 'PLMB', 2),
    (new.id, 'Electrical', 'ELEC', 3),
    (new.id, 'Fire Protection', 'FP', 4),
    (new.id, 'Structural Steel', 'STL', 5),
    (new.id, 'Framing / Drywall', 'FRM', 6),
    (new.id, 'Low Voltage', 'LV', 7),
    (new.id, 'Controls', 'CTRL', 8),
    (new.id, 'Facade', 'FCD', 9);
  if auth.uid() is not null then
    insert into project_members (project_id, user_id, role)
    values (new.id, auth.uid(), 'coordinator') on conflict do nothing;
  end if;
  return null;
end;
$$;

drop trigger if exists projects_seed on public.projects;
create trigger projects_seed after insert on public.projects
  for each row execute function public.project_seed();

create or replace function public.code_upper() returns trigger
language plpgsql as $$
begin
  new.code := upper(trim(new.code));
  return new;
end;
$$;

-- A trade that is on any item can be renamed but not deleted.
create or replace function public.trade_delete_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Deleting the whole project removes everything; no check needed.
  if not exists (select 1 from projects where id = old.project_id) then
    return old;
  end if;
  if exists (select 1 from items where project_id = old.project_id
             and (old.id = any(trade_ids) or bic_trade_id = old.id)) then
    raise exception 'This trade is used on coordination items. Rename it instead of deleting it.';
  end if;
  return old;
end;
$$;

drop trigger if exists trades_delete_guard on public.project_trades;
create trigger trades_delete_guard before delete on public.project_trades
  for each row execute function public.trade_delete_guard();

drop trigger if exists trades_code on public.project_trades;
create trigger trades_code before insert or update on public.project_trades
  for each row execute function public.code_upper();
drop trigger if exists types_code on public.item_types;
create trigger types_code before insert or update on public.item_types
  for each row execute function public.code_upper();

-- ---------------------------------------------------------------------
-- 6. Coordination items: numbering, permission rules, history
-- ---------------------------------------------------------------------

create or replace function public.check_item_trades(pid uuid, tids uuid[]) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from unnest(tids) t
             where not exists (select 1 from project_trades where id = t and project_id = pid)) then
    raise exception 'One of the trades does not belong to this project.';
  end if;
end;
$$;

-- New item: number it (project code - type code - 001), stamp who and when.
create or replace function public.item_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  pcode text;
  tcode text;
  n int;
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  new.trade_ids := coalesce(new.trade_ids, '{}');
  if new.bic_trade_id is not null and not (new.bic_trade_id = any(new.trade_ids)) then
    new.trade_ids := array_append(new.trade_ids, new.bic_trade_id);
  end if;
  perform check_item_trades(new.project_id, new.trade_ids);

  select code into pcode from projects where id = new.project_id;
  select code into tcode from item_types where id = new.type_id and project_id = new.project_id;
  if tcode is null then
    raise exception 'That item type does not belong to this project.';
  end if;

  insert into item_counters (project_id, type_id, last_serial)
  values (new.project_id, new.type_id, 1)
  on conflict (project_id, type_id) do update set last_serial = item_counters.last_serial + 1
  returning last_serial into n;

  new.serial := n;
  new.number := pcode || '-' || tcode || '-' || lpad(n::text, 3, '0');
  new.bic_since := now();
  new.created_at := now();
  new.updated_at := now();
  if new.status = 'closed' then
    new.closed_at := now();
    new.closed_by := new.created_by;
  else
    new.closed_at := null;
    new.closed_by := null;
  end if;
  return new;
end;
$$;

drop trigger if exists items_before_insert on public.items;
create trigger items_before_insert before insert on public.items
  for each row execute function public.item_before_insert();

-- Changes to an item. Rules:
--  * Admin / coordinator: may change anything except the number, project and type.
--  * Trade lead / member (their trade is involved or holds the ball):
--      - may set status to Response Submitted or Model Updated (not on closed,
--        voided or on-hold items),
--      - may pass the ball, only while their trade holds it, to another involved
--        trade or back to the coordinator,
--      - may not change anything else.
--  * Viewer: read only.
--  * Submitting a response or marking the model updated sends the ball back to
--    the coordinator (unless it was passed somewhere else in the same change).
create or replace function public.item_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r text := public.member_role(old.project_id);
  trade_cols text[] := array['status', 'bic_trade_id', 'bic_since', 'updated_at', 'closed_at', 'closed_by'];
begin
  if new.id <> old.id or new.project_id <> old.project_id or new.serial <> old.serial
     or new.number <> old.number or new.type_id <> old.type_id
     or new.created_by <> old.created_by or new.created_at <> old.created_at then
    raise exception 'The item number, project and type cannot change.';
  end if;

  if auth.uid() is not null then
    if r is null or r = 'viewer' then
      raise exception 'You have read-only access to this project.';
    end if;
    if r in ('trade_lead', 'trade_member') then
      if (to_jsonb(new) - trade_cols) <> (to_jsonb(old) - trade_cols) then
        raise exception 'Trades can submit a response, mark the model updated or pass the ball. Ask the coordinator to change anything else.';
      end if;
      if new.status is distinct from old.status
         and not (new.status in ('response_submitted', 'model_updated')
                  and old.status in ('open', 'in_review', 'response_submitted', 'model_updated')) then
        raise exception 'Only the coordinator can close, void, hold or reopen an item.';
      end if;
      if new.bic_trade_id is distinct from old.bic_trade_id then
        if old.bic_trade_id is distinct from public.my_trade(old.project_id) then
          raise exception 'Only the trade that holds the ball can pass it.';
        end if;
        if new.bic_trade_id is not null and not (new.bic_trade_id = any(old.trade_ids)) then
          raise exception 'The ball can only go to a trade involved in this item, or back to the coordinator.';
        end if;
      end if;
    end if;
  end if;

  if new.status is distinct from old.status and new.status in ('response_submitted', 'model_updated')
     and new.bic_trade_id is not distinct from old.bic_trade_id then
    new.bic_trade_id := null;
  end if;

  new.trade_ids := coalesce(new.trade_ids, '{}');
  if new.bic_trade_id is not null and not (new.bic_trade_id = any(new.trade_ids)) then
    new.trade_ids := array_append(new.trade_ids, new.bic_trade_id);
  end if;
  if new.trade_ids is distinct from old.trade_ids then
    perform check_item_trades(new.project_id, new.trade_ids);
  end if;

  if new.bic_trade_id is distinct from old.bic_trade_id then
    new.bic_since := now();
  else
    new.bic_since := old.bic_since;
  end if;

  if new.status = 'closed' and old.status <> 'closed' then
    new.closed_at := now();
    new.closed_by := auth.uid();
  elsif new.status <> 'closed' then
    new.closed_at := null;
    new.closed_by := null;
  else
    new.closed_at := old.closed_at;
    new.closed_by := old.closed_by;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists items_before_update on public.items;
create trigger items_before_update before update on public.items
  for each row execute function public.item_before_update();

-- History log + notifications after every change.
create or replace function public.item_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  label text := new.number || ' · ' || new.title;
  changed text[] := '{}';
begin
  if tg_op = 'INSERT' then
    insert into item_events (item_id, actor_id, kind, to_value) values (new.id, me, 'created', new.status);
    if new.bic_trade_id is not null then
      insert into item_events (item_id, actor_id, kind, from_value, to_value)
      values (new.id, me, 'ball', '', trade_label(new.bic_trade_id));
      perform notify_users(trade_people(new.project_id, array[new.bic_trade_id]), new.project_id, new.id,
        'ball', new.number || ' · Ball in your court', new.title);
    end if;
    perform notify_users(
      array(select unnest(trade_people(new.project_id, new.trade_ids))
            except select unnest(trade_people(new.project_id, array[new.bic_trade_id]))),
      new.project_id, new.id, 'new_item', new.number || ' · New item for your trade', new.title);
    return null;
  end if;

  if new.status is distinct from old.status then
    insert into item_events (item_id, actor_id, kind, from_value, to_value) values (new.id, me, 'status', old.status, new.status);
    if new.status in ('response_submitted', 'model_updated') then
      perform notify_users(coordinators(new.project_id), new.project_id, new.id, 'response',
        new.number || case when new.status = 'response_submitted' then ' · Response submitted' else ' · Model updated – verify' end,
        new.title);
    elsif new.status = 'closed' then
      perform notify_users(trade_people(new.project_id, new.trade_ids), new.project_id, new.id, 'closed',
        new.number || ' · Closed', new.title);
    end if;
  end if;

  if new.bic_trade_id is distinct from old.bic_trade_id then
    insert into item_events (item_id, actor_id, kind, from_value, to_value)
    values (new.id, me, 'ball', trade_label(old.bic_trade_id), trade_label(new.bic_trade_id));
    if new.bic_trade_id is null then
      if new.status not in ('response_submitted', 'model_updated') or new.status is not distinct from old.status then
        perform notify_users(coordinators(new.project_id), new.project_id, new.id, 'ball',
          new.number || ' · Ball back with the coordinator', new.title);
      end if;
    else
      perform notify_users(trade_people(new.project_id, array[new.bic_trade_id]), new.project_id, new.id, 'ball',
        new.number || ' · Ball in your court', new.title);
    end if;
  end if;

  if new.priority is distinct from old.priority then
    insert into item_events (item_id, actor_id, kind, from_value, to_value) values (new.id, me, 'priority', old.priority, new.priority);
  end if;
  if new.due_date is distinct from old.due_date then
    insert into item_events (item_id, actor_id, kind, from_value, to_value)
    values (new.id, me, 'due', coalesce(old.due_date::text, ''), coalesce(new.due_date::text, ''));
  end if;
  if new.needs_rfi is distinct from old.needs_rfi or new.rfi_number is distinct from old.rfi_number then
    insert into item_events (item_id, actor_id, kind, from_value, to_value)
    values (new.id, me, 'rfi', case when old.needs_rfi then 'RFI ' || old.rfi_number else '' end,
                               case when new.needs_rfi then 'RFI ' || new.rfi_number else '' end);
  end if;

  if new.title is distinct from old.title then changed := array_append(changed, 'title'); end if;
  if new.description is distinct from old.description then changed := array_append(changed, 'description'); end if;
  if (new.building, new.level, new.zone, new.grid) is distinct from (old.building, old.level, old.zone, old.grid) then
    changed := array_append(changed, 'location');
  end if;
  if (new.clash_test, new.clash_id, new.viewpoint, new.revit_ids, new.sheet)
     is distinct from (old.clash_test, old.clash_id, old.viewpoint, old.revit_ids, old.sheet) then
    changed := array_append(changed, 'model reference');
  end if;
  if new.trade_ids is distinct from old.trade_ids then changed := array_append(changed, 'trades'); end if;
  if cardinality(changed) > 0 then
    insert into item_events (item_id, actor_id, kind, to_value) values (new.id, me, 'edited', array_to_string(changed, ', '));
  end if;
  return null;
end;
$$;

drop trigger if exists items_after_change on public.items;
create trigger items_after_change after insert or update on public.items
  for each row execute function public.item_after_change();

-- Discussion: stamp author, notify the people on the item.
create or replace function public.comment_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then new.author_id := auth.uid(); end if;
    new.created_at := now();
    new.edited_at := null;
  else
    if new.item_id <> old.item_id or new.author_id <> old.author_id or new.created_at <> old.created_at then
      raise exception 'Only the text of a comment can be edited.';
    end if;
    new.edited_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists comments_before on public.item_comments;
create trigger comments_before before insert or update on public.item_comments
  for each row execute function public.comment_before();

create or replace function public.comment_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  it record;
  who text;
begin
  select * into it from items where id = new.item_id;
  select name into who from profiles where id = new.author_id;
  perform notify_users(trade_people(it.project_id, it.trade_ids) || coordinators(it.project_id),
    it.project_id, it.id, 'comment', it.number || ' · New reply from ' || coalesce(who, 'someone'),
    left(case when new.body <> '' then new.body else 'Attachment' end, 140));
  return null;
end;
$$;

drop trigger if exists comments_after on public.item_comments;
create trigger comments_after after insert on public.item_comments
  for each row execute function public.comment_after();

-- ---------------------------------------------------------------------
-- 7. Row level security (who can see and change what)
-- ---------------------------------------------------------------------

alter table public.profiles        enable row level security;
alter table public.projects        enable row level security;
alter table public.project_trades  enable row level security;
alter table public.item_types      enable row level security;
alter table public.project_members enable row level security;
alter table public.items           enable row level security;
alter table public.item_counters   enable row level security;
alter table public.item_comments   enable row level security;
alter table public.item_events     enable row level security;
alter table public.notifications   enable row level security;
alter table public.invites         enable row level security;

-- profiles: yourself, people on your projects, and everyone for the admin.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin() or (public.is_approved() and public.shares_project(id)));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles for delete to authenticated
  using (public.is_admin() and id <> auth.uid());

-- projects: only the ones you are on (the admin sees all); only the admin changes them.
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to authenticated
  using (public.is_member(id));
drop policy if exists projects_admin on public.projects;
create policy projects_admin on public.projects for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- trades and item types
drop policy if exists trades_select on public.project_trades;
create policy trades_select on public.project_trades for select to authenticated
  using (public.is_member(project_id));
drop policy if exists trades_admin on public.project_trades;
create policy trades_admin on public.project_trades for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists types_select on public.item_types;
create policy types_select on public.item_types for select to authenticated
  using (public.is_member(project_id));
drop policy if exists types_admin on public.item_types;
create policy types_admin on public.item_types for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- project team
drop policy if exists members_select on public.project_members;
create policy members_select on public.project_members for select to authenticated
  using (public.is_member(project_id));
drop policy if exists members_admin on public.project_members;
create policy members_admin on public.project_members for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- items
drop policy if exists items_select on public.items;
create policy items_select on public.items for select to authenticated
  using (public.is_member(project_id));
drop policy if exists items_insert on public.items;
create policy items_insert on public.items for insert to authenticated
  with check (public.is_coord(project_id));
drop policy if exists items_update on public.items;
create policy items_update on public.items for update to authenticated
  using (
    public.is_coord(project_id)
    or (public.member_role(project_id) in ('trade_lead', 'trade_member')
        and (public.my_trade(project_id) = any(trade_ids) or public.my_trade(project_id) = bic_trade_id))
  )
  with check (public.is_member(project_id));
drop policy if exists items_delete on public.items;
create policy items_delete on public.items for delete to authenticated
  using (public.is_admin());

-- item_counters: only the numbering trigger touches it (no policies = no direct access).

-- discussion
drop policy if exists comments_select on public.item_comments;
create policy comments_select on public.item_comments for select to authenticated
  using (public.can_see_item(item_id));
drop policy if exists comments_insert on public.item_comments;
create policy comments_insert on public.item_comments for insert to authenticated
  with check (
    author_id = auth.uid()
    and exists (select 1 from public.items i where i.id = item_id
                and public.member_role(i.project_id) in ('admin', 'coordinator', 'trade_lead', 'trade_member'))
  );
drop policy if exists comments_update on public.item_comments;
create policy comments_update on public.item_comments for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());
drop policy if exists comments_delete on public.item_comments;
create policy comments_delete on public.item_comments for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

-- history (written only by triggers)
drop policy if exists events_select on public.item_events;
create policy events_select on public.item_events for select to authenticated
  using (public.can_see_item(item_id));

-- notifications: your own only
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid());
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications for delete to authenticated
  using (user_id = auth.uid());

-- invitations / member suggestions
drop policy if exists invites_select on public.invites;
create policy invites_select on public.invites for select to authenticated
  using (public.is_admin() or suggested_by = auth.uid());
drop policy if exists invites_insert on public.invites;
create policy invites_insert on public.invites for insert to authenticated
  with check (public.is_admin() or public.member_role(project_id) = 'trade_lead');
drop policy if exists invites_admin_update on public.invites;
create policy invites_admin_update on public.invites for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists invites_admin_delete on public.invites;
create policy invites_admin_delete on public.invites for delete to authenticated
  using (public.is_admin());

-- Nobody signed out can read anything.
revoke all on all tables in schema public from anon;

-- ---------------------------------------------------------------------
-- 8. Live updates
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['items', 'item_comments', 'item_events', 'notifications',
                             'project_members', 'project_trades', 'item_types', 'projects', 'profiles', 'invites'] loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', t);
      exception when duplicate_object then null;
      end;
    end loop;
  end if;
end $$;

-- Accounts that already existed before this script: give them a profile.
insert into public.profiles (id, name, email, is_admin, status)
select u.id,
       coalesce(nullif(u.raw_user_meta_data ->> 'name', ''), split_part(u.email, '@', 1)),
       lower(u.email),
       (row_number() over (order by u.created_at) = 1) and not exists (select 1 from public.profiles where is_admin),
       'approved'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;
