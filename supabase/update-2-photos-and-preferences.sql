-- =====================================================================
-- Christman Coordination Workspace — update 2 (version 0.2)
--   * photos on coordination items and in replies (private file storage)
--   * each person's own look: theme, colors, font and text size
-- Safe to run more than once.
-- =====================================================================

alter table public.items    add column if not exists photos text[] not null default '{}';
alter table public.profiles add column if not exists prefs  jsonb  not null default '{}'::jsonb;

-- Photo changes show in the item's history as "Edited: photos".
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
  if new.photos is distinct from old.photos then changed := array_append(changed, 'photos'); end if;
  if cardinality(changed) > 0 then
    insert into item_events (item_id, actor_id, kind, to_value) values (new.id, me, 'edited', array_to_string(changed, ', '));
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- File storage: private bucket, folders named <project id>/<item id>/<file>.
-- Only people on the project can see the files; everyone except viewers can add them.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('files', 'files', false)
on conflict (id) do nothing;

-- The project id from the first folder of a stored file's path (null if it is not an id).
create or replace function public.file_project(path text) returns uuid
language sql immutable set search_path = public as $$
  select case when split_part(path, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(path, '/', 1)::uuid end;
$$;

drop policy if exists coord_files_read on storage.objects;
create policy coord_files_read on storage.objects for select to authenticated
  using (bucket_id = 'files' and public.file_project(name) is not null and public.is_member(public.file_project(name)));

drop policy if exists coord_files_write on storage.objects;
create policy coord_files_write on storage.objects for insert to authenticated
  with check (
    bucket_id = 'files' and public.file_project(name) is not null
    and public.member_role(public.file_project(name)) in ('admin', 'coordinator', 'trade_lead', 'trade_member')
  );

drop policy if exists coord_files_delete on storage.objects;
create policy coord_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'files' and public.is_admin());
