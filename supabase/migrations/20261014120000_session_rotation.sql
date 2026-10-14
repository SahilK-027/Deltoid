-- Which rotation a training day alternates in.
--
-- Two days of one regime that share a value hold one position in the cycle
-- between them, and each cycle trains one of them. A regime that trains Leg 1
-- in one cycle and Leg 2 in the next is two days carrying the same value.
--
-- Nullable and not backfilled, matching the local column: null means the day
-- is trained every cycle, which is what every existing row meant when it was
-- written.
--
-- No check constraint, as with `bar_kind`: the local column carries one, and
-- the server's job is to hold the row.
--
-- Applied before any build that knows the column. A push sends every key of a
-- row, so a phone on the new build is refused by a server without it.
alter table public.sessions
  add column if not exists rotation_id text;
