-- TrueFocus sync, end to end. Applied to the shared Supabase project (fcfbsgvkanuywsmxvuee)
-- as migration truefocus_e2e.
--
-- Devices now send an access token derived one way from the space key (HKDF, "access.v1")
-- instead of the space key itself, so the server never holds what the payload key is derived
-- from. tf_space() is unchanged: it hashes whatever x-tf-space carries.

-- One-time move of a space from its legacy id, sha256(space key), to sha256(access token).
-- Called once per device with the legacy key in x-tf-space. Merges by last writer wins, so
-- devices upgrading at different times (and a device still writing to the legacy space) lose
-- nothing. Returns the number of records moved.
create or replace function public.tf_rekey(p_access text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  old_space text := public.tf_space();
  new_space text;
  moved integer := 0;
begin
  if old_space is null or p_access is null or length(p_access) < 32 then
    raise exception 'invalid space' using errcode = '22023';
  end if;
  new_space := encode(extensions.digest(p_access, 'sha256'), 'hex');
  if new_space = old_space then
    return 0;
  end if;

  -- The stamp trigger skips an update whose modified_at is older, so the newer edit wins.
  insert into public.tf_records (space, id, kind, data, deleted, modified_at)
    select new_space, id, kind, data, deleted, modified_at
    from public.tf_records where space = old_space
  on conflict (space, id) do update
    set kind = excluded.kind, data = excluded.data, deleted = excluded.deleted,
        modified_at = excluded.modified_at;
  get diagnostics moved = row_count;
  delete from public.tf_records where space = old_space;

  insert into public.tf_devices (space, token, platform, environment, updated_at)
    select new_space, token, platform, environment, updated_at
    from public.tf_devices where space = old_space
  on conflict (space, token) do update
    set platform = excluded.platform, environment = excluded.environment, updated_at = excluded.updated_at;
  delete from public.tf_devices where space = old_space;

  return moved;
end $$;

-- Deletes everything stored for the caller's space: records and push tokens.
create or replace function public.tf_delete_space() returns void
language plpgsql security definer set search_path = '' as $$
declare
  s text := public.tf_space();
begin
  if s is null then
    raise exception 'invalid space' using errcode = '22023';
  end if;
  delete from public.tf_records where space = s;
  delete from public.tf_devices where space = s;
end $$;

revoke all on function public.tf_rekey(text), public.tf_delete_space() from public;
grant execute on function public.tf_rekey(text), public.tf_delete_space() to anon, authenticated;

-- Linking without handing the server the key: the devices swap X25519 public keys through
-- tf-pair and the key travels sealed. space_key is '' for those rows; it holds a key only for
-- builds that predate this (drop the column once none are left).
alter table public.tf_pairings
  add column if not exists host_pk text,
  add column if not exists guest_pk text,
  add column if not exists box text;
