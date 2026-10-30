-- The RLS policies on `cycle_rests`, the eleventh syncable table.
--
-- `rls_test.sql` exercises `set_logs` in full and holds every table to having
-- row level security at all. `cycle_rests` arrived in a migration of its own,
-- so it gets its own case (SYNC § 4), for the reason `phases` does: a policy
-- nobody has executed is a policy nobody has checked.
--
--   supabase test db

begin;

create extension if not exists pgtap with schema extensions;

select plan(7);

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

-- Alice rests a day of her deload.
select sign_in_as(:'alice');

select lives_ok(
  $$insert into public.cycle_rests (id, updated_at, device_id, dirty,
      cycle_id, session_id, day_key)
    values ('rest-alice', 1, 'phone-a', true, 'cycle-7', 'push-1', 20261117)$$,
  'a signed-in account can write its own rest day'
);

select is(
  (select user_id from public.cycle_rests where id = 'rest-alice'),
  :'alice'::uuid,
  'user_id is attached from the session, not from the client'
);

select isnt(
  (select server_updated_at from public.cycle_rests where id = 'rest-alice'),
  null,
  'the server stamps its own clock on a rest day'
);

-- Bob signs in on another phone entirely.
select sign_in_as(:'bob');

select results_eq(
  $$select count(*)::int from public.cycle_rests$$,
  array[0],
  'Bob cannot read a rest day that is not his — `using`'
);

select throws_ok(
  $$insert into public.cycle_rests (id, updated_at, device_id, dirty,
      cycle_id, session_id, day_key, user_id)
    values ('rest-forged', 1, 'phone-b', true, 'cycle-7', 'push-1', 20261117,
            '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Bob cannot write a rest day onto Alice''s account — `with check`'
);

update public.cycle_rests set day_key = 20261118 where id = 'rest-alice';

select sign_in_as(:'alice');
select is(
  (select day_key from public.cycle_rests where id = 'rest-alice'),
  20261117::bigint,
  'Bob''s edit touches nothing, and Alice''s rest day is as she left it'
);

-- Two rests for one day are stored, not refused. Both phones read the set of
-- rested days, in which a second copy changes nothing (SYNC § 9).
select lives_ok(
  $$insert into public.cycle_rests (id, updated_at, device_id, dirty,
      cycle_id, session_id, day_key)
    values ('rest-alice-2', 2, 'phone-b', true, 'cycle-7', 'push-1', 20261117)$$,
  'a second rest for one day is stored for the phones to read as one'
);

select * from finish();

rollback;
