-- Days of a deload rested instead of trained: the eleventh syncable table.
--
-- Designed in SYNC.md § 4 (what the server holds), § 9 (why two rests for one
-- day need no rule) and § 12 rows 23 to 25. It takes the shape of the other
-- ten exactly: the local columns, `user_id` from the session, the server's
-- clock stamped by trigger, an index for the pull cursor, and row level
-- security with `using` and `with check`.
--
-- Like the first migration, it declares no CHECK constraints, no foreign keys
-- and no enum type. The local columns are the gate: `day_key` is checked on
-- the phone, and a server that refused the same row would strand it dirty with
-- nothing able to clear it.
--
-- Applied with `supabase db push` before any build that knows the table is
-- installed on a synced phone. Installed first, the build's pushes of rest
-- rows are refused and wait as dirty until this lands (SYNC § 13).

create table if not exists public.cycle_rests (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  cycle_id              text not null,
  session_id            text not null,
  day_key               bigint not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists cycle_rests_user_cursor
  on public.cycle_rests (user_id, server_updated_at);

drop trigger if exists stamp_cycle_rests_server_updated_at on public.cycle_rests;
create trigger stamp_cycle_rests_server_updated_at
  before insert or update on public.cycle_rests
  for each row execute function public.stamp_server_updated_at();

alter table public.cycle_rests enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
drop policy if exists "own rows only" on public.cycle_rests;
create policy "own rows only" on public.cycle_rests
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it reaches nothing at all.
grant select, insert, update, delete on public.cycle_rests to authenticated;
