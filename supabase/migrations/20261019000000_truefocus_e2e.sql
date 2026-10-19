-- TrueFocus sync, end to end. Applied to the shared Supabase project (fcfbsgvkanuywsmxvuee).
--
-- Devices now send an access token derived one way from the space key (HKDF, "access.v1")
-- instead of the space key itself, so the server never holds what the payload key is derived
-- from. tf_space() is unchanged: it hashes whatever x-tf-space carries.

-- The one-time move off the legacy id (sha256 of the space key) and "Delete server copy" live in
-- the tf-space edge function (service role, scoped to the space in x-tf-space).

-- Linking without handing the server the key: the devices swap X25519 public keys through
-- tf-pair and the key travels sealed. space_key is '' for those rows; it holds a key only for
-- builds that predate this (drop the column once none are left).
-- The host first stores only host_commit = sha256(its public key). The joiner claims the code
-- (guest_claim, random) and gets the commitment before it sends guest_pk; the host reveals host_pk
-- only after guest_pk is in. So no key can be chosen after seeing the other side's.
alter table public.tf_pairings
  add column if not exists host_commit text,
  add column if not exists guest_claim text,
  add column if not exists host_pk text,
  add column if not exists guest_pk text,
  add column if not exists box text;
