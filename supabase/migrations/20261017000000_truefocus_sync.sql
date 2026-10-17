-- Applied to the shared Supabase project (fcfbsgvkanuywsmxvuee) as migrations
-- truefocus_sync + truefocus_sync_policies; this is their combined final state.

-- TrueFocus sync. Everything is prefixed tf_ and is independent of the rest of this project.
-- No auth users: a device proves which "space" it belongs to with a secret key sent in the
-- x-tf-space header. Only its SHA-256 is stored. Payloads are encrypted on device.

create extension if not exists pgcrypto with schema extensions;

-- The space for this request: sha256(x-tf-space), or null when the key is missing/short.
create or replace function public.tf_space() returns text
language sql stable security invoker set search_path = '' as $$
  select case when length(h) >= 32
              then encode(extensions.digest(h, 'sha256'), 'hex') end
  from (select coalesce(current_setting('request.headers', true)::json ->> 'x-tf-space', '') as h) s
$$;

create table public.tf_records (
  space text not null default public.tf_space(),
  id uuid not null,
  kind text not null check (kind in ('task', 'segment', 'plan', 'note')),
  data jsonb not null default '{}'::jsonb,
  deleted boolean not null default false,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (space, id)
);
create index tf_records_space_updated_idx on public.tf_records (space, updated_at);
comment on table public.tf_records is 'TrueFocus app sync records (encrypted payloads). Not used by ListingLine.';

-- Last writer wins by device modification time; updated_at is the server cursor.
create or replace function public.tf_records_stamp() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.modified_at < old.modified_at then
      return null;           -- an older edit never overwrites a newer one
    end if;
    new.space := old.space;  -- rows never move between spaces
  end if;
  new.updated_at := clock_timestamp();
  return new;
end $$;

create trigger tf_records_stamp
  before insert or update on public.tf_records
  for each row execute function public.tf_records_stamp();

alter table public.tf_records enable row level security;
create policy tf_records_select on public.tf_records for select to anon, authenticated
  using (space = public.tf_space());
create policy tf_records_insert on public.tf_records for insert to anon, authenticated
  with check (space = public.tf_space());
create policy tf_records_update on public.tf_records for update to anon, authenticated
  using (space = public.tf_space()) with check (space = public.tf_space());

-- Push tokens for silent sync wake-ups.
create table public.tf_devices (
  space text not null default public.tf_space(),
  token text not null,
  platform text not null check (platform in ('ios', 'macos')),
  environment text not null default 'development' check (environment in ('development', 'production')),
  updated_at timestamptz not null default now(),
  primary key (space, token)
);
comment on table public.tf_devices is 'TrueFocus push tokens. Not used by ListingLine.';
alter table public.tf_devices enable row level security;
create policy tf_devices_select on public.tf_devices for select to anon, authenticated
  using (space = public.tf_space());
create policy tf_devices_insert on public.tf_devices for insert to anon, authenticated
  with check (space = public.tf_space());
create policy tf_devices_update on public.tf_devices for update to anon, authenticated
  using (space = public.tf_space()) with check (space = public.tf_space());

-- Pairing codes, only ever touched by the tf-pair edge function (service role). No policies.
create table public.tf_pairings (
  code text primary key,
  space_key text not null,
  expires_at timestamptz not null
);
create table public.tf_pair_failures (
  at timestamptz not null default now()
);
comment on table public.tf_pairings is 'TrueFocus device-link codes (10 min). Service role only.';
alter table public.tf_pairings enable row level security;
alter table public.tf_pair_failures enable row level security;
revoke all on public.tf_pairings, public.tf_pair_failures from anon, authenticated;
revoke delete on public.tf_records, public.tf_devices from anon, authenticated;
