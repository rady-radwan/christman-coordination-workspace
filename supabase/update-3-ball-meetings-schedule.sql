-- =====================================================================
-- Christman Coordination Workspace — update 3 (version 0.3)
--   * the ball can be in several trades' court at once
--   * coordination meetings with minutes
--   * coordination schedule
--   * project coordination start / end dates (for "coordination week N")
-- Run after schema.sql and update-2. Safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Ball in court: several trades (empty list = the Christman coordinator)
-- ---------------------------------------------------------------------

alter table public.items add column if not exists bic_trade_ids uuid[] not null default '{}';

do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'items' and column_name = 'bic_trade_id') then
    update public.items set bic_trade_ids = array[bic_trade_id]
    where bic_trade_id is not null and bic_trade_ids = '{}';
    -- The update rule below is recreated for the new column; triggers are replaced below too.
    drop policy if exists items_update on public.items;
    alter table public.items drop column bic_trade_id;
  end if;
end $$;

-- Sorted list without repeats, so two lists can be compared.
create or replace function public.uuid_set(a uuid[]) returns uuid[]
language sql immutable as $$
  select coalesce(array(select distinct x from unnest(a) x where x is not null order by x), '{}');
$$;

-- "Mechanical + Plumbing", or "Christman VDC" for the coordinator.
create or replace function public.trades_label(tids uuid[]) returns text
language sql stable security definer set search_path = public as $$
  select case when coalesce(cardinality(tids), 0) = 0 then 'Christman VDC'
              else coalesce((select string_agg(name, ' + ' order by sort, name) from project_trades where id = any(tids)), 'Christman VDC')
         end;
$$;

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
  new.bic_trade_ids := uuid_set(new.bic_trade_ids);
  new.trade_ids := uuid_set(coalesce(new.trade_ids, '{}') || new.bic_trade_ids);
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

-- Rules for trades (admin and coordinators may change anything except number, project and type):
--  * submit a response / mark the model updated (not on closed, voided or on-hold items);
--    their own trade then leaves the ball, and when nobody is left it goes back to the coordinator;
--  * pass the ball while their trade holds it, to trades on the item, keeping the other holders;
--  * nothing else.
create or replace function public.item_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r text := public.member_role(old.project_id);
  mine uuid := public.my_trade(old.project_id);
  trade_cols text[] := array['status', 'bic_trade_ids', 'bic_since', 'updated_at', 'closed_at', 'closed_by'];
  ball_changed boolean;
begin
  if new.id <> old.id or new.project_id <> old.project_id or new.serial <> old.serial
     or new.number <> old.number or new.type_id <> old.type_id
     or new.created_by <> old.created_by or new.created_at <> old.created_at then
    raise exception 'The item number, project and type cannot change.';
  end if;

  new.bic_trade_ids := uuid_set(new.bic_trade_ids);
  ball_changed := new.bic_trade_ids is distinct from uuid_set(old.bic_trade_ids);

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
      if ball_changed then
        if mine is null or not (mine = any(old.bic_trade_ids)) then
          raise exception 'Only a trade that holds the ball can pass it.';
        end if;
        if exists (select 1 from unnest(new.bic_trade_ids) t
                   where not t = any(old.trade_ids) and not t = any(old.bic_trade_ids)) then
          raise exception 'The ball can only go to trades involved in this item, or back to the coordinator.';
        end if;
        if exists (select 1 from unnest(old.bic_trade_ids) t where t <> mine and not t = any(new.bic_trade_ids)) then
          raise exception 'You can only pass your own trade''s part of the ball.';
        end if;
      end if;
    end if;
  end if;

  -- A response or model update hands the ball back: a trade drops its own part,
  -- a coordinator setting it clears the list (ball with the coordinator).
  if new.status is distinct from old.status and new.status in ('response_submitted', 'model_updated') and not ball_changed then
    if r in ('trade_lead', 'trade_member') then
      new.bic_trade_ids := uuid_set(array_remove(new.bic_trade_ids, mine));
    else
      new.bic_trade_ids := '{}';
    end if;
    ball_changed := new.bic_trade_ids is distinct from uuid_set(old.bic_trade_ids);
  end if;

  new.trade_ids := uuid_set(coalesce(new.trade_ids, '{}') || new.bic_trade_ids);
  if new.trade_ids is distinct from uuid_set(old.trade_ids) then
    perform check_item_trades(new.project_id, new.trade_ids);
  else
    new.trade_ids := old.trade_ids;
  end if;

  if ball_changed then
    new.bic_since := now();
  else
    new.bic_trade_ids := old.bic_trade_ids;
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

create or replace function public.item_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  changed text[] := '{}';
  added uuid[];
begin
  if tg_op = 'INSERT' then
    insert into item_events (item_id, actor_id, kind, to_value) values (new.id, me, 'created', new.status);
    if cardinality(new.bic_trade_ids) > 0 then
      insert into item_events (item_id, actor_id, kind, from_value, to_value)
      values (new.id, me, 'ball', '', trades_label(new.bic_trade_ids));
      perform notify_users(trade_people(new.project_id, new.bic_trade_ids), new.project_id, new.id,
        'ball', new.number || ' · Ball in your court', new.title);
    end if;
    perform notify_users(
      array(select unnest(trade_people(new.project_id, new.trade_ids))
            except select unnest(trade_people(new.project_id, new.bic_trade_ids))),
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

  if new.bic_trade_ids is distinct from old.bic_trade_ids then
    insert into item_events (item_id, actor_id, kind, from_value, to_value)
    values (new.id, me, 'ball', trades_label(old.bic_trade_ids), trades_label(new.bic_trade_ids));
    added := array(select unnest(new.bic_trade_ids) except select unnest(old.bic_trade_ids));
    if cardinality(added) > 0 then
      perform notify_users(trade_people(new.project_id, added), new.project_id, new.id, 'ball',
        new.number || ' · Ball in your court', new.title);
    end if;
    if cardinality(new.bic_trade_ids) = 0
       and (new.status not in ('response_submitted', 'model_updated') or new.status is not distinct from old.status) then
      perform notify_users(coordinators(new.project_id), new.project_id, new.id, 'ball',
        new.number || ' · Ball back with the coordinator', new.title);
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
  if new.photos is distinct from old.photos then changed := array_append(changed, 'photos'); end if;
  if cardinality(changed) > 0 then
    insert into item_events (item_id, actor_id, kind, to_value) values (new.id, me, 'edited', array_to_string(changed, ', '));
  end if;
  return null;
end;
$$;

create or replace function public.trade_delete_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from projects where id = old.project_id) then
    return old;
  end if;
  if exists (select 1 from items where project_id = old.project_id
             and (old.id = any(trade_ids) or old.id = any(bic_trade_ids))) then
    raise exception 'This trade is used on coordination items. Rename it instead of deleting it.';
  end if;
  return old;
end;
$$;

drop policy if exists items_update on public.items;
create policy items_update on public.items for update to authenticated
  using (
    public.is_coord(project_id)
    or (public.member_role(project_id) in ('trade_lead', 'trade_member')
        and (public.my_trade(project_id) = any(trade_ids) or public.my_trade(project_id) = any(bic_trade_ids)))
  )
  with check (public.is_member(project_id));

-- Every trade in the ball list must belong to the project.
create or replace function public.check_item_trades(pid uuid, tids uuid[]) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from unnest(tids) t
             where not exists (select 1 from project_trades where id = t and project_id = pid)) then
    raise exception 'One of the trades does not belong to this project.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Project coordination dates
-- ---------------------------------------------------------------------

alter table public.projects add column if not exists coordination_start date;
alter table public.projects add column if not exists coordination_end date;

-- ---------------------------------------------------------------------
-- 3. Coordination meetings
-- ---------------------------------------------------------------------

create table if not exists public.meetings (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid not null references public.projects (id) on delete cascade,
  number        int  not null default 0,
  title         text not null check (length(trim(title)) > 0),
  starts_at     timestamptz not null,
  duration_min  int  not null default 60 check (duration_min between 5 and 600),
  location      text not null default '',
  attendees     jsonb not null default '[]'::jsonb,  -- [{name, company, role, present}]
  summary       text not null default '',
  items         jsonb not null default '[]'::jsonb,  -- [{id, number, title, status, priority, ball, note}]
  actions       jsonb not null default '[]'::jsonb,  -- [{text, owner, due, done}]
  next_meeting  timestamptz,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists meetings_project_idx on public.meetings (project_id, starts_at desc);

-- Meeting numbers per project: 1, 2, 3 …
create or replace function public.meeting_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtext('meeting-' || new.project_id::text));
    select coalesce(max(number), 0) + 1 into new.number from meetings where project_id = new.project_id;
    if auth.uid() is not null then new.created_by := auth.uid(); end if;
    new.created_at := now();
  else
    if new.project_id <> old.project_id or new.number <> old.number then
      raise exception 'The meeting number and project cannot change.';
    end if;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists meetings_before on public.meetings;
create trigger meetings_before before insert or update on public.meetings
  for each row execute function public.meeting_before();

alter table public.meetings enable row level security;
drop policy if exists meetings_select on public.meetings;
create policy meetings_select on public.meetings for select to authenticated
  using (public.is_member(project_id));
drop policy if exists meetings_write on public.meetings;
create policy meetings_write on public.meetings for all to authenticated
  using (public.is_coord(project_id)) with check (public.is_coord(project_id));

-- ---------------------------------------------------------------------
-- 4. Coordination schedule
-- ---------------------------------------------------------------------

create table if not exists public.schedule_tasks (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  kind        text not null default 'coordination'
              check (kind in ('coordination', 'sign_off', 'model_due', 'milestone', 'other')),
  area        text not null default '',
  start_date  date not null,
  end_date    date not null,
  trade_ids   uuid[] not null default '{}',
  percent     int  not null default 0 check (percent between 0 and 100),
  notes       text not null default '',
  sort        int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (end_date >= start_date)
);
create index if not exists schedule_project_idx on public.schedule_tasks (project_id, start_date);

create or replace function public.touch_updated() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists schedule_touch on public.schedule_tasks;
create trigger schedule_touch before update on public.schedule_tasks
  for each row execute function public.touch_updated();

alter table public.schedule_tasks enable row level security;
drop policy if exists schedule_select on public.schedule_tasks;
create policy schedule_select on public.schedule_tasks for select to authenticated
  using (public.is_member(project_id));
drop policy if exists schedule_write on public.schedule_tasks;
create policy schedule_write on public.schedule_tasks for all to authenticated
  using (public.is_coord(project_id)) with check (public.is_coord(project_id));

revoke all on public.meetings, public.schedule_tasks from anon;

-- ---------------------------------------------------------------------
-- 5. Live updates
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['meetings', 'schedule_tasks'] loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', t);
      exception when duplicate_object then null;
      end;
    end loop;
  end if;
end $$;
