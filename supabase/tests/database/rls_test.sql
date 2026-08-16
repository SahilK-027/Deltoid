-- The RLS policies, which are the whole of the security.
--
-- The anon key ships inside the APK and is extractable (SYNC § 3). What stops
-- it being a public database with a guessable filter is these policies, and a
-- policy that has never been executed is a policy nobody has checked. The fake
-- backend the Dart tests run against cannot check this — it has no Postgres and
-- no `auth.uid()` — so this is the one suite that needs a real stack:
--
--   supabase test db
--
-- Nine tables, and `set_logs` is the one exercised in full: the policies are
-- generated identically, so the interesting question is whether the *shape* is
-- right, not whether the ninth copy was pasted correctly. The last test holds
-- all nine to having it at all.

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- Two accounts that have never heard of each other.
\set alice '11111111-1111-1111-1111-111111111111'
\set bob   '22222222-2222-2222-2222-222222222222'

create or replace function sign_in_as(uid uuid) returns void as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', uid::text, 'role', 'authenticated')::text,
    true
  );
end;
$$ language plpgsql;

-- Alice logs a set.
select sign_in_as(:'alice');

select lives_ok(
  $$insert into public.set_logs (id, updated_at, device_id, dirty,
      workout_exercise_id, set_index, set_type, is_done)
    values ('set-alice', 1, 'phone-a', true, 'we-alice', 0, 'working', true)$$,
  'a signed-in account can write its own row'
);

select is(
  (select user_id from public.set_logs where id = 'set-alice'),
  :'alice'::uuid,
  'user_id is attached from the session, not from the client'
);

select isnt(
  (select server_updated_at from public.set_logs where id = 'set-alice'),
  null,
  'the server stamps its own clock on insert'
);

select results_eq(
  $$select count(*)::int from public.set_logs$$,
  array[1],
  'Alice sees her own row'
);

-- Bob signs in on another phone entirely.
select sign_in_as(:'bob');

select results_eq(
  $$select count(*)::int from public.set_logs$$,
  array[0],
  'Bob cannot read a row that is not his — `using`'
);

select throws_ok(
  $$insert into public.set_logs (id, updated_at, device_id, dirty,
      workout_exercise_id, set_index, set_type, is_done, user_id)
    values ('set-forged', 1, 'phone-b', true, 'we-b', 0, 'working', true,
            '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Bob cannot write a row onto Alice''s account — `with check`'
);

-- An update that matches nothing is not an error, it is a no-op — which is the
-- point: Bob's client cannot tell Alice's row exists, and cannot change it.
update public.set_logs set reps = 99 where id = 'set-alice';
select is(
  (select count(*)::int from public.set_logs where id = 'set-alice'),
  0,
  'Bob''s update touches nothing, because he cannot see the row'
);

select sign_in_as(:'alice');
select is(
  (select reps from public.set_logs where id = 'set-alice'),
  null,
  'and Alice''s row is exactly as she left it'
);

-- Every one of the nine, not only the one above.
select results_eq(
  $$select count(*)::int from pg_tables
    where schemaname = 'public' and rowsecurity = false$$,
  array[0],
  'no table in public is left without row level security'
);

select * from finish();

rollback;
