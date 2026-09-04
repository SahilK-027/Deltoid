-- Which bar, per training day, and which bar it actually was.
--
-- Two columns for one idea, and they answer different questions.
--
-- `session_exercises.bar_kind` is the decision: this movement is loaded on
-- that bar *in this day*. The same lift is not trained the same way in two
-- days — a back squat off the rack and one off a women's bar are two different
-- empty weights — and the catalog can only hold one answer for both.
--
-- `workout_exercises.bar_kind` is the snapshot of what was used. The plate
-- diagram read the catalog live, so changing a bar silently redrew the plates
-- of every session ever logged; what went on the bar in March is a fact about
-- March. Same rule as `workout_exercises.muscle`, one column over.
--
-- Nullable on both, and null is not `none`. Null means "no answer here, follow
-- the catalog", which is exactly what every existing row meant when it was
-- written. `none` is a decision — that this movement sits on no bar at all —
-- and defaulting to it would take the plate diagram away from every barbell set
-- already logged. Nothing is backfilled for the same reason.
--
-- No check constraint, matching `muscle` beside it: the local column carries
-- one, and the server's job is to hold the row rather than to re-litigate it.
-- An unknown string is refused at the phone that reads it, which is the end
-- that can be rebuilt.
--
-- Separate rungs rather than an edit to `20260816095036_sync_tables.sql`, which
-- has already been applied — `create table if not exists` would skip the new
-- columns on the project that is live.
alter table public.session_exercises
  add column if not exists bar_kind text;

alter table public.workout_exercises
  add column if not exists bar_kind text;
