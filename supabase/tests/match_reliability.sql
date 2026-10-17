-- Privileged fixtures stay inside this rolled-back transaction. REST tests
-- separately exercise real anonymous JWTs, concurrency and snapshot privacy.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select ok(not exists (
  select 1 from pg_tables t cross join unnest(array['anon','authenticated']) r(role)
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
  where t.schemaname='private' and t.tablename like 'arena_%'
    and has_table_privilege(r.role,format('%I.%I',t.schemaname,t.tablename),p.privilege)
), 'neither client role can read or mutate any private match table');
select ok(not has_function_privilege('anon',
  'public.arena_issue_arrival_approval(text,text,text)','EXECUTE'), 'unauthenticated users cannot issue approvals');
select ok(not (select prosecdef from pg_proc
  where oid='public.arena_issue_arrival_approval(text,text,text)'::regprocedure), 'approval wrapper is invoker');
select is((select array_agg(schemaname||'.'||tablename order by tablename)
  from pg_publication_tables where pubname='supabase_realtime'),
  array['public.arena_invalidations','public.battle_invalidations'],
  'Realtime publishes only safe invalidations');
select columns_are('public','battle_invalidations',array['id','revision'],
  'battle notifications contain only an ID and revision, never answers or locations');
select ok((select relrowsecurity from pg_class
  where oid='public.battle_invalidations'::regclass), 'battle notifications enforce RLS');
select ok(has_table_privilege('authenticated','public.battle_invalidations','SELECT'),
  'authenticated members can request battle notifications through RLS');
select ok(not exists (
  select 1 from unnest(array['anon','authenticated']) r(role)
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p(privilege)
  where not (r.role='authenticated' and p.privilege='SELECT')
    and has_table_privilege(r.role,'public.battle_invalidations',p.privilege)
), 'battle notifications deny anonymous reads and all client writes');

insert into auth.users(id,raw_user_meta_data,raw_app_meta_data) values
  ('00000000-0000-4000-8000-000000000101','{"arenaOrganiser":true}','{}'),
  ('00000000-0000-4000-8000-000000000102','{}','{}'),
  ('00000000-0000-4000-8000-000000000103','{}','{"arenaOrganiser":true}');
insert into private.arena_rooms(id,code,creator_id,course_id,course_version,algorithm) values
  ('10000000-0000-4000-8000-000000000101','AABBCC0101','00000000-0000-4000-8000-000000000101',
    'gilmorehill-jms-library','candidate-2026-10-17-1','dijkstra'),
  ('10000000-0000-4000-8000-000000000102','AABBCC0102','00000000-0000-4000-8000-000000000101',
    'gilmorehill-jms-library','candidate-2026-10-17-1','dijkstra');
insert into private.arena_players(room_id,user_id,seat,nickname)
select r.id,u.id,u.seat,'Test' from private.arena_rooms r cross join (values
  ('00000000-0000-4000-8000-000000000101'::uuid,1),
  ('00000000-0000-4000-8000-000000000102'::uuid,2)) u(id,seat)
where r.id in ('10000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000102');

-- Helpers construct valid envelopes, without bypassing the real command rules.
create function pg_temp.arrive(proof text,room_id uuid default '10000000-0000-4000-8000-000000000101')
returns jsonb language sql as $$
  select public.arena_command(jsonb_build_object('contractVersion',1,'id',gen_random_uuid(),
    'scope',jsonb_build_object('match',jsonb_build_object('matchID',r.id,'expectedRevision',r.revision,
      'course',jsonb_build_object('id',r.course_id,'version',r.course_version))),
    'action',jsonb_build_object('confirmArrival',jsonb_build_object('nodeID','01-jms',
      'evidence',jsonb_build_object('organiserApproval',jsonb_build_object('approvalID',proof))))))
  from private.arena_rooms r where r.id=$2;
$$;
create function pg_temp.issue(player_id text default '00000000-0000-4000-8000-000000000101')
returns jsonb language sql as $$
  select public.arena_issue_arrival_approval('10000000-0000-4000-8000-000000000101',$1,'01-jms');
$$;
create temp table proofs(name text primary key,document jsonb);

set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101"}';
select throws_like($$select pg_temp.issue()$$,'%invalidApproval%',
  'room creator and user-editable metadata cannot grant organiser authority');
select throws_like($$select pg_temp.arrive('fake')$$,'%invalidApproval%', 'invalid approval is rejected');
select is((select count(*)::integer from private.arena_arrivals where room_id='10000000-0000-4000-8000-000000000101'),
  0, 'invalid proof leaves no arrival');

set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000103"}';
insert into proofs values ('guest',pg_temp.issue('00000000-0000-4000-8000-000000000102')),
  ('expired',pg_temp.issue()),('valid',pg_temp.issue());
select is((select count(*)::integer from private.arena_arrival_approvals
  where issuer_id='00000000-0000-4000-8000-000000000103'),3, 'every issued approval is logged privately');
select ok((select bool_and(expires_at>created_at and expires_at<=created_at+interval '121 seconds')
  from private.arena_arrival_approvals where issuer_id='00000000-0000-4000-8000-000000000103'),
  'proof lifetime is two minutes');
update private.arena_arrival_approvals set expires_at=clock_timestamp()-interval '1 second'
  where id::text=(select document->>'approvalID' from proofs where name='expired');

set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101"}';
select throws_like($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='guest'))$$,
  '%invalidApproval%', 'proof is bound to its player');
select throws_like($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='valid'),
  '10000000-0000-4000-8000-000000000102')$$,'%invalidApproval%', 'proof is bound to its room');
select throws_like($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='expired'))$$,
  '%invalidApproval%', 'expired proof is rejected without waiting in the test');
update private.arena_arrival_approvals set node_id='wrong-node'
  where id::text=(select document->>'approvalID' from proofs where name='valid');
select throws_like($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='valid'))$$,
  '%invalidApproval%', 'proof is bound to its checkpoint');
update private.arena_arrival_approvals set node_id='01-jms'
  where id::text=(select document->>'approvalID' from proofs where name='valid');
select lives_ok($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='valid'))$$,
  'valid organiser proof confirms arrival');
select is((select count(*)::integer from private.arena_arrival_approvals
  where issuer_id='00000000-0000-4000-8000-000000000103' and used_at is not null),1,
  'successful redemption is logged exactly once');
select is((select method from private.arena_arrivals where room_id='10000000-0000-4000-8000-000000000101'
  and user_id='00000000-0000-4000-8000-000000000101'),'organiserApproval', 'arrival records the override method');
select throws_like($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='valid'))$$,
  '%invalidPhase%', 'new command cannot redeem an arrival twice');

-- Revocation is checked in auth.users even if a JWT still carries the old claim.
update auth.users set raw_app_meta_data='{}' where id='00000000-0000-4000-8000-000000000103';
set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000103","app_metadata":{"arenaOrganiser":true}}';
select throws_like($$select pg_temp.issue()$$,'%invalidApproval%', 'revoked organiser cannot use a stale JWT claim');
update auth.users set raw_app_meta_data='{"arenaOrganiser":true}' where id='00000000-0000-4000-8000-000000000103';

-- Seed just below each limit, then exercise the real issuing/redemption path.
insert into private.arena_arrival_approvals(room_id,user_id,node_id,issuer_id)
select '10000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000102','01-jms',
  '00000000-0000-4000-8000-000000000103' from generate_series(1,26);
select lives_ok($$select pg_temp.issue('00000000-0000-4000-8000-000000000102')$$,
  '30th organiser issuance in a minute succeeds');
select throws_like($$select pg_temp.issue()$$,'%rateLimited%retryAfterSeconds%60%',
  '31st organiser issuance returns a bounded retry delay');
update private.arena_arrival_approvals set used_at=clock_timestamp() where id in
  (select id from private.arena_arrival_approvals where user_id='00000000-0000-4000-8000-000000000102'
    and id::text<>(select document->>'approvalID' from proofs where name='guest') limit 5);
set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102"}';
select throws_like($$select pg_temp.arrive((select document->>'approvalID' from proofs where name='guest'))$$,
  '%rateLimited%retryAfterSeconds%60%', 'sixth redemption per player/match is rate limited');
select ok((select used_at is null from private.arena_arrival_approvals where id::text=
  (select document->>'approvalID' from proofs where name='guest')), 'rate-limited attempt does not consume proof');

insert into private.arena_submissions(room_id,user_id,challenge_id,command_id,answer,correct) values
  ('10000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000101',
    'learning-dijkstra-first-v1',gen_random_uuid(),'{"node":{"nodeID":"A"}}',true);
insert into private.arena_rewards values ('10000000-0000-4000-8000-000000000102',
  '00000000-0000-4000-8000-000000000101','first',20);
select throws_like($$update private.arena_submissions set correct=false
  where room_id='10000000-0000-4000-8000-000000000102'$$,'%immutable%', 'first answer cannot be edited');
select throws_like($$delete from private.arena_submissions
  where room_id='10000000-0000-4000-8000-000000000102'$$,'%immutable%', 'first answer cannot be deleted');
select throws_like($$update private.arena_rewards set points=0
  where room_id='10000000-0000-4000-8000-000000000102'$$,'%immutable%', 'reward cannot be edited');
select throws_like($$delete from private.arena_rewards
  where room_id='10000000-0000-4000-8000-000000000102'$$,'%immutable%', 'reward cannot be deleted');

set local role authenticated;
select throws_like($$select * from private.arena_challenges$$,'%permission denied%', 'answer bank is inaccessible to client role');
select throws_like($$select * from private.arena_submissions$$,'%permission denied%', 'raw answers are inaccessible to client role');
select throws_like($$select * from private.arena_rewards$$,'%permission denied%', 'raw rewards are inaccessible to client role');
select throws_like($$select * from private.arena_arrival_approvals$$,'%permission denied%', 'override proofs and audit records are inaccessible to client role');
reset role;
select * from finish();
rollback;
