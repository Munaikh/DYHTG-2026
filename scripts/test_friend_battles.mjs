// Isolated PostgreSQL tests. npm install --prefix /tmp/arena-db @electric-sql/pglite
// PGLITE_MODULE=/tmp/arena-db/node_modules/@electric-sql/pglite/dist/index.js node scripts/test_friend_battles.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const a='11111111-1111-4111-8111-111111111111', b='22222222-2222-4222-8222-222222222222', c='33333333-3333-4333-8333-333333333333';
await db.exec(`create role anon; create role authenticated; create schema auth; create schema private;
create table auth.users(id uuid primary key,email text,is_anonymous boolean default false);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create publication supabase_realtime; grant usage on schema private,auth to authenticated;`);
await db.exec(fs.readFileSync(new URL('../supabase/migrations/20261017203000_friend_battles.sql',import.meta.url),'utf8'));
await db.query(`insert into auth.users(id,email) values($1,'a@example.test'),($2,'b@example.test'),($3,'c@example.test')`,[a,b,c]);
const call=async (who,action,payload={})=> {
  await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[who]);
  return (await db.query(`select public.friend_battle($1,$2::jsonb) state`,[action,JSON.stringify(payload)])).rows[0].state;
};
const reject=async (fn,pattern)=>assert.rejects(fn,pattern);
try {
  await reject(()=>call('','create'),/Sign in/);
  for (const [who,name] of [[a,'Alex'],[b,'Sam'],[c,'Outside']]) await call(who,'profile',{nickname:name});
  let room=await call(a,'create'); const id=room.id;
  await reject(()=>call(c,'snapshot',{id}),/Room unavailable/);
  await reject(()=>call(a,'create'),/existing room/);
  await call(b,'join',{code:room.code});
  await reject(()=>call(c,'join',{code:room.code}),/full/);
  await reject(()=>call(a,'requestLocation',{id}),/scheduled expiry/);
  await db.exec('update private.battle_configuration set cleanup_ready=true');
  await call(a,'requestLocation',{id});
  let view=await call(b,'snapshot',{id});
  assert.equal(view.sharing.accepted,false);assert.deepEqual(view.sharing.positions,{});
  await reject(()=>call(a,'position',{id,latitude:55,longitude:-4}),/consent/);
  await reject(()=>call(a,'acceptLocation',{id}),/expired/);
  await call(b,'acceptLocation',{id});
  await call(a,'position',{id,latitude:55,longitude:-4});
  view=await call(b,'snapshot',{id});assert.equal(view.sharing.positions[a].latitude,55);
  await reject(()=>call(c,'snapshot',{id}),/unavailable/);
  await call(b,'stopLocation',{id});view=await call(a,'snapshot',{id});assert.equal(view.sharing,null);
  await call(a,'requestLocation',{id});await call(b,'acceptLocation',{id});await call(a,'position',{id,latitude:55,longitude:-4});
  await db.query(`update private.battle_sharing set expires_at=now()-interval '1 second' where battle=$1`,[id]);
  assert.equal((await call(a,'snapshot',{id})).sharing,null);
  assert.equal((await db.query(`select count(*)::int n from private.battle_sharing where battle=$1`,[id])).rows[0].n,0);
  await call(a,'ready',{id,ready:true});room=await call(b,'ready',{id,ready:true});assert.equal(room.phase,'playing');
  const first=await call(a,'snapshot',{id});assert.deepEqual(first.challenge,room.challenge);
  assert.equal('answer' in room.challenge,false);assert.equal('solution' in room.challenge,false);
  room=await call(a,'submit',{id,round:1,answer:[0,99]});assert.equal(room.feedback.correct,false);assert.equal(room.players.find(p=>p.id===a).score,0);
  // Server-private answers are used only by this privileged test harness.
  const kinds=new Set();
  while(room.phase==='playing') {
    const me=room.players.find(p=>p.id===a), round=me.round; kinds.add(room.challenge.kind);
    const answer=(await db.query(`select answer from private.battle_answers where battle=$1 and round=$2`,[id,round])).rows[0].answer;
    await db.query(`update private.battle_seats set last_attempt=null where battle=$1 and player=$2`,[id,a]);
    room=await call(a,'submit',{id,round,answer});assert.equal(room.feedback.correct,true);
    if(room.phase==='playing') await reject(()=>call(a,'submit',{id,round,answer}),/already been submitted/);
  }
  assert.deepEqual([...kinds].sort(),['binary','dfs','path','sort']);
  assert.equal(room.winner,a);
  const statsA=await call(a,'stats'), statsB=await call(b,'stats');
  assert.equal(statsA.profile.nickname,'Alex');assert.equal(statsB.profile.nickname,'Sam');
  assert.equal(statsA.wins,1);assert.equal(statsA.matches,1);assert.equal(statsA.currentStreak,1);assert.equal(statsA.bestStreak,1);
  assert.equal(statsB.wins,0);assert.equal(statsB.matches,1);
  await reject(()=>call(a,'submit',{id,round:1,answer:[0]}),/not active/);
  assert.equal((await call(a,'stats')).matches,1);
  let rematch=await call(a,'rematch',{id});const next=rematch.rematch;assert.ok(next);
  assert.equal((await call(b,'rematch',{id})).rematch,next);
  room=await call(a,'snapshot',{id:next});assert.equal(room.players.length,2);assert.ok(room.players.every(p=>p.score===0 && !p.ready));
  await call(a,'ready',{id:next,ready:true});await call(b,'ready',{id:next,ready:true});
  await db.query(`update private.battle_seats set last_seen=now()-interval '30 seconds' where battle=$1 and player=$2`,[next,b]);
  await reject(()=>call(a,'submit',{id:next,round:1,answer:[0]}),/disconnected/);
  await db.query(`update private.battle_seats set last_seen=now()-interval '6 minutes' where battle=$1 and player=$2`,[next,b]);
  room=await call(a,'snapshot',{id:next});assert.equal(room.phase,'abandoned');assert.equal((await call(a,'stats')).matches,1);
  // Direct mutations and answer reads must be inaccessible to an API caller.
  await db.exec('set role authenticated');
  assert.equal((await call(a,'stats')).matches,1);
  await call(c,'stats');
  assert.equal((await db.query('select * from public.battle_invalidations')).rows.length,0);
  await reject(()=>db.query(`select * from private.battle_answers`),/permission denied/);
  await reject(()=>db.query(`update public.battle_invalidations set revision=999`),/permission denied/);
  await db.exec('reset role');
  console.log('PASS: auth, membership, lobby, shared challenges, BFS/DFS/Dijkstra/A*/sorting/binary-search challenges, verified scoring, idempotency, stats, rematch, disconnects and location consent/expiry.');
} finally { await db.close(); }
