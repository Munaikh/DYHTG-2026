begin;
create extension if not exists pgtap with schema extensions;
select plan(26);
select ok((select bool_and(relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p') and ((n.nspname='private' and c.relname like 'arena_%')
     or (n.nspname='public' and c.relname='arena_invalidations'))), 'RLS enabled on every arena table');
select ok(not has_table_privilege('anon', 'public.arena_invalidations', 'SELECT'), 'anon cannot read invalidations');
select ok(has_table_privilege('authenticated', 'public.arena_invalidations', 'SELECT'), 'authenticated can read with RLS');
select ok(not has_table_privilege('authenticated', 'public.arena_invalidations', 'INSERT'), 'no client invalidation inserts');
select ok(not has_table_privilege('authenticated', 'public.arena_invalidations', 'UPDATE'), 'no client invalidation updates');
select ok(not has_table_privilege('authenticated', 'public.arena_invalidations', 'DELETE'), 'no client invalidation deletes');
select ok(not has_table_privilege('authenticated', 'private.arena_rooms', 'SELECT'), 'no raw room reads');
select ok(not has_table_privilege('authenticated', 'private.arena_players', 'UPDATE'), 'no identity/arrival/ready writes');
select ok(not has_table_privilege('authenticated', 'private.arena_command_receipts', 'SELECT'), 'no raw private receipt reads');
select ok(not has_function_privilege('anon', 'public.arena_command(jsonb)', 'EXECUTE'), 'anon cannot invoke commands');
select ok(not has_function_privilege('anon', 'public.arena_snapshot(text)', 'EXECUTE'), 'anon cannot invoke snapshots');
select ok(has_function_privilege('authenticated', 'public.arena_command(jsonb)', 'EXECUTE'), 'signed-in anonymous sessions can invoke commands');
select ok(not (select prosecdef from pg_proc where oid='public.arena_command(jsonb)'::regprocedure), 'public command wrapper uses invoker');
select ok(not (select prosecdef from pg_proc where oid='public.arena_snapshot(text)'::regprocedure), 'public snapshot wrapper uses invoker');
select ok(not has_function_privilege('anon', 'private.arena_command(jsonb)', 'EXECUTE'), 'private implementation excludes anon');
select ok(not has_function_privilege('authenticated', 'private.arena_fail(text,text,integer)', 'EXECUTE'), 'internal helper is not callable by clients');
select is((select count(*)::integer from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='private'), 0, 'private tables never replicate');
select is((select array_agg(attname::text order by attname) from pg_attribute
  where attrelid='public.arena_invalidations'::regclass and attnum>0 and not attisdropped),
  array['matchID','revision'], 'replication contains only match ID and revision');
select ok((select bool_and('search_path=""'=any(proconfig)) from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.prosecdef),
  'all private privileged entry points use an empty search path');

select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE')),
  'no exposed privileged function is executable by anon');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef and has_function_privilege('authenticated',p.oid,'EXECUTE')),
  'no exposed privileged function is executable by authenticated');

-- Fixed users exist only inside this rolled-back test transaction.
insert into auth.users(id) values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000003');
insert into private.arena_rooms(id, code, creator_id, course_id, course_version, algorithm) values
  ('10000000-0000-4000-8000-000000000001', 'ABCDEF1234',
   '00000000-0000-4000-8000-000000000001', 'gilmorehill-jms-library', 'candidate-2026-10-17-1', 'dijkstra');
insert into private.arena_players(room_id,user_id,seat,nickname) values
  ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',1,'Host'),
  ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',2,'Guest');
select throws_like($$insert into private.arena_players(room_id,user_id,seat,nickname) values
  ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003',3,'Third')$$,
  '%violates check constraint%', 'database capacity constraint blocks a third seat');
select throws_like($$update private.arena_players set ready=true where
  room_id='10000000-0000-4000-8000-000000000001'$$,
  '%violates check constraint%', 'database prevents ready without confirmation');

set local role authenticated;
set local request.jwt.claims = '{}';
select throws_like($$select public.arena_snapshot('10000000-0000-4000-8000-000000000001')$$,
  '%unauthenticated%', 'privileged snapshot checks auth even if role is authenticated');
select throws_like($$select public.arena_command('{}')$$,
  '%unauthenticated%', 'privileged command checks auth even if role is authenticated');
select is(private.arena_is_member('10000000-0000-4000-8000-000000000001'), false,
  'RLS membership helper denies missing identity');
reset role;
select * from finish();
rollback;
