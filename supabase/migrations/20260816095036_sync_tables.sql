-- Deltoid — the nine syncable tables, and the security that is the whole point.
--
-- Designed in SYNC.md § 4 (what the server holds), § 3 (identity and RLS) and
-- § 17 (the wire). Read those before changing anything here: the parts that are
-- expensive to get wrong are the parts nothing on a phone can see.
--
-- Three things this file deliberately does NOT do.
--
--   * **No CHECK constraints.** The local column is the backstop for a number
--     that cannot mean anything (RULES § 2), and a server that refuses the same
--     row instead strands it dirty forever with nothing able to clear it. The
--     phone refuses bad rows; the server stores what it is given.
--
--   * **No foreign keys**, for exactly the same reason. Push order is
--     parents-before-children so referential order holds in practice, but a
--     server-side rejection is unrecoverable from the phone's side in a way a
--     local one never is — the row stays dirty and every later push retries it.
--
--   * **No enum types.** Postgres enums would make adding one value a migration
--     on both sides; the local CHECK is the gate that matters.
--
-- `dirty` is stored here and never read here. It means "this device still owes
-- the server", which is nonsense once the row has arrived — but the wire is a
-- row's `toJson` and the columns mirror the local table exactly, which is what
-- lets one registry describe both ends and one test hold them to it. A pull
-- applier lands every row with `dirty = false` whatever the column says.
--
-- `app_settings` is not here and never will be. It holds `device_id`, the unit
-- preference and the theme — which phone you are on, and how that phone should
-- look. Syncing `device_id` would break the tie-break it exists for (SYNC § 4).

-- The clock every conflict is decided on.
--
-- `updated_at` is a phone's wall clock, and two phones do not agree on it: a
-- device running ten minutes fast would win every conflict it is ever in and
-- the other device's edits would vanish silently. Agreement between devices is
-- a server's job. Stamped here rather than accepted from the client, so it
-- cannot be forged by the device that benefits from forging it (SYNC § 8).
create or replace function public.stamp_server_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

create table if not exists public.exercises (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  name                  text not null,
  muscle                text not null,
  equipment             text not null,
  load_mode             text not null,
  measure_mode          text not null,
  bar_kind              text not null,
  starter_key           text,
  form_video_urls       text not null,
  notes                 text,
  archived              boolean not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists exercises_user_cursor
  on public.exercises (user_id, server_updated_at);

create trigger stamp_exercises_server_updated_at
  before insert or update on public.exercises
  for each row execute function public.stamp_server_updated_at();

alter table public.exercises enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.exercises
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.exercises to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.regimes (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  name                  text not null,
  is_active             boolean not null,
  deload_enabled        boolean not null,
  deload_after_cycles   bigint not null,
  deload_set_delta      bigint not null,
  deload_weight_pct     bigint not null,
  identity_index        bigint not null,
  created_at            bigint not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists regimes_user_cursor
  on public.regimes (user_id, server_updated_at);

create trigger stamp_regimes_server_updated_at
  before insert or update on public.regimes
  for each row execute function public.stamp_server_updated_at();

alter table public.regimes enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.regimes
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.regimes to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.sessions (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  regime_id             text not null,
  name                  text not null,
  order_index           bigint not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists sessions_user_cursor
  on public.sessions (user_id, server_updated_at);

create trigger stamp_sessions_server_updated_at
  before insert or update on public.sessions
  for each row execute function public.stamp_server_updated_at();

alter table public.sessions enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.sessions
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.sessions to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.session_exercises (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  session_id            text not null,
  exercise_id           text not null,
  order_index           bigint not null,
  target_sets           bigint not null,
  target_rep_low        bigint,
  target_rep_high       bigint,
  notes                 text,
  rest_seconds          bigint,
  deload_set_delta      bigint,
  deload_weight_pct     bigint,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists session_exercises_user_cursor
  on public.session_exercises (user_id, server_updated_at);

create trigger stamp_session_exercises_server_updated_at
  before insert or update on public.session_exercises
  for each row execute function public.stamp_server_updated_at();

alter table public.session_exercises enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.session_exercises
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.session_exercises to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.cycles (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  regime_id             text not null,
  cycle_index           bigint not null,
  started_at            bigint not null,
  completed_at          bigint,
  is_deload             boolean not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists cycles_user_cursor
  on public.cycles (user_id, server_updated_at);

create trigger stamp_cycles_server_updated_at
  before insert or update on public.cycles
  for each row execute function public.stamp_server_updated_at();

alter table public.cycles enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.cycles
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.cycles to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.workouts (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  regime_id             text not null,
  session_id            text,
  cycle_id              text,
  day_key               bigint not null,
  started_at            bigint not null,
  tz_offset_minutes     bigint not null,
  ended_at              bigint,
  is_deload             boolean not null,
  status                text not null,
  notes                 text,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists workouts_user_cursor
  on public.workouts (user_id, server_updated_at);

create trigger stamp_workouts_server_updated_at
  before insert or update on public.workouts
  for each row execute function public.stamp_server_updated_at();

alter table public.workouts enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.workouts
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.workouts to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.workout_exercises (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  workout_id            text not null,
  exercise_id           text not null,
  order_index           bigint not null,
  target_sets           bigint not null,
  notes                 text,
  skip_reason           text not null,
  muscle                text,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists workout_exercises_user_cursor
  on public.workout_exercises (user_id, server_updated_at);

create trigger stamp_workout_exercises_server_updated_at
  before insert or update on public.workout_exercises
  for each row execute function public.stamp_server_updated_at();

alter table public.workout_exercises enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.workout_exercises
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.workout_exercises to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.set_logs (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  workout_exercise_id   text not null,
  set_index             bigint not null,
  set_type              text not null,
  weight                double precision,
  reps                  bigint,
  partial_reps          bigint,
  added_weight          double precision,
  parent_set_id         text,
  rest_seconds          bigint,
  completed_at          bigint,
  note                  text,
  is_done               boolean not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists set_logs_user_cursor
  on public.set_logs (user_id, server_updated_at);

create trigger stamp_set_logs_server_updated_at
  before insert or update on public.set_logs
  for each row execute function public.stamp_server_updated_at();

alter table public.set_logs enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.set_logs
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.set_logs to authenticated;

-- --------------------------------------------------------------------------

create table if not exists public.bodyweight_logs (
  id                    text not null,
  updated_at            bigint not null,
  deleted_at            bigint,
  device_id             text not null,
  dirty                 boolean not null,
  day_key               bigint not null,
  weight_kg             double precision not null,
  user_id               uuid not null default auth.uid(),
  server_updated_at     timestamptz not null default now(),
  primary key (id)
);

-- Every pull query there will ever be: this account's rows, since a cursor.
create index if not exists bodyweight_logs_user_cursor
  on public.bodyweight_logs (user_id, server_updated_at);

create trigger stamp_bodyweight_logs_server_updated_at
  before insert or update on public.bodyweight_logs
  for each row execute function public.stamp_server_updated_at();

alter table public.bodyweight_logs enable row level security;

-- `with check` as well as `using`, or a client can write rows it then
-- cannot read. SYNC § 3.
create policy "own rows only" on public.bodyweight_logs
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- To `authenticated` only, never `anon`. The anon key ships inside the APK
-- and is extractable; without a session it now reaches nothing at all,
-- rather than reaching a table whose policy happens to match no rows.
grant select, insert, update, delete on public.bodyweight_logs to authenticated;
