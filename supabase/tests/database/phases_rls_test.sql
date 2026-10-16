-- The RLS policies on `phases`, the tenth syncable table.
--
-- `rls_test.sql` exercises `set_logs` in full and holds every table to having
-- row level security at all. `phases` arrived in a migration of its own, so it
-- gets its own case (SYNC § 4): the policy, the grant and the trigger were
-- written by hand rather than generated beside the other nine, and a policy
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

-- Alice declares a cut.
select sign_in_as(:'alice');

select lives_ok(
  $$insert into public.phases (id, updated_at, device_id, dirty, kind, day_key,
      planned_weeks)
    values ('phase-alice', 1, 'phone-a', true, 'cut', 20260903, 12)$$,
  'a signed-in account can write its own phase'
);

select is(
  (select user_id from public.phases where id = 'phase-alice'),
  :'alice'::uuid,
  'user_id is attached from the session, not from the client'
);

select isnt(
  (select server_updated_at from public.phases where id = 'phase-alice'),
  null,
  'the server stamps its own clock on a phase'
);

-- Bob signs in on another phone entirely.
select sign_in_as(:'bob');

select results_eq(
  $$select count(*)::int from public.phases$$,
  array[0],
  'Bob cannot read a phase that is not his — `using`'
);

select throws_ok(
  $$insert into public.phases (id, updated_at, device_id, dirty, kind, day_key,
      user_id)
    values ('phase-forged', 1, 'phone-b', true, 'bulk', 20260903,
            '11111111-1111-1111-1111-111111111111')$$,
  '42501',
  null,
  'Bob cannot write a phase onto Alice''s account — `with check`'
);

update public.phases set end_day_key = 20260910 where id = 'phase-alice';

select sign_in_as(:'alice');
select is(
  (select end_day_key from public.phases where id = 'phase-alice'),
  null::bigint,
  'Bob''s clear touches nothing, and Alice''s phase is as she left it'
);

-- Two phases on one start day are stored, not refused. The pull applier
-- settles them (SYNC § 9); a server that refused the second would strand it
-- dirty on the phone that sent it.
select lives_ok(
  $$insert into public.phases (id, updated_at, device_id, dirty, kind, day_key)
    values ('phase-alice-2', 2, 'phone-b', true, 'bulk', 20260903)$$,
  'a second phase on one start day is stored for the phones to settle'
);

select * from finish();

rollback;
