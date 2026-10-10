-- How much of the lifter's bodyweight a bodyweight movement moves.
--
-- A push-up leaves the feet on the floor and moves about two thirds of the
-- body; a pull-up moves nearly all of it. Every bodyweight movement was scored
-- on the whole bodyweight, which overstates the push-up's load by half.
--
-- 100 by default and not null, matching the local column: that is what every
-- existing row meant when it was written. The phones backfill the movements
-- the app seeded itself and push them, so nothing is backfilled here.
--
-- No check constraint, as with `bar_kind`: the local column carries one, and
-- the server's job is to hold the row.
--
-- Applied before any build that knows the column. A push sends every key of a
-- row, so a phone on the new build is refused by a server without it.
alter table public.exercises
  add column if not exists bodyweight_pct bigint not null default 100;
