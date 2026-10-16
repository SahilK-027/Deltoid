-- Bulk, cut and maintenance: the tenth syncable table.
--
-- Designed in SYNC.md § 4 (what the server holds), § 9 (the one collision a
-- phase can be in) and § 12 rows 19 to 22. It takes the shape of the other
-- nine exactly: the local columns, `user_id` from the session, the server's
-- clock stamped by trigger, an index for the pull cursor, and row level
-- security with `using` and `with check`.
--
-- Like the first migration, it declares no CHECK constraints, no foreign keys
-- and no enum type. The local columns are the gate: `kind` is checked against
-- the three phases on the phone, and a server that refused the same row would
-- strand it dirty with nothing able to clear it. A phase names no regime, so
-- there is no foreign key it could even have.
--
-- Nor is there a unique index on the start day. Two phones that both start a
-- phase on one day are making one statement twice, and the pull applier
-- tombstones the older (SYNC § 9, `phases_start_live`). A server-side unique
-- index would refuse the second push instead, and that row would stay dirty
-- forever.
--
-- Applied with `supabase db push` before any build that knows the table is
-- installed on a synced phone. Installed first, the build's pushes of phase
-- rows are refused and wait as dirty until this lands (SYNC § 13).

create table if not exists public.phases (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  kind                  text not null,
  day_key               bigint not null,
  planned_weeks         bigint,
  end_day_key           bigint,
  kept_day_key          bigint,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists phases_user_cursor
  on public.phases (user_id, server_updated_at);

drop trigger if exists stamp_phases_server_updated_at on public.phases;
create trigger stamp_phases_server_updated_at
  before insert or update on public.phases
  for each row execute function public.stamp_server_updated_at();

alter table public.phases enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
drop policy if exists "own rows only" on public.phases;
create policy "own rows only" on public.phases
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it reaches nothing at all.
grant select, insert, update, delete on public.phases to authenticated;
