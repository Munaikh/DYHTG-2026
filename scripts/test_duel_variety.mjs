// Isolated PostgreSQL test. Uses PGLITE_MODULE as documented in docs/DUEL.md.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import fs from 'node:fs';
const {PGlite}=await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db=new PGlite();
const host=randomUUID(),guest=randomUUID(),outsider=randomUUID();
let checks=0;
try {
  await db.exec(`create role anon;create role authenticated;create schema auth;
    create table auth.users(id uuid primary key,email text,is_anonymous boolean default true,raw_app_meta_data jsonb);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated;create publication supabase_realtime;`);
  // Load the real migration chain, including historical answer fixtures.
  for(const file of fs.readdirSync(new URL('../supabase/migrations/',import.meta.url)).sort()) {
    await db.exec(fs.readFileSync(new URL(`../supabase/migrations/${file}`,import.meta.url),'utf8'));
  }
  await db.query('insert into auth.users(id) values($1),($2),($3)',[host,guest,outsider]);
  async function call(who,command) {
    await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[who]);
    return (await db.query('select public.arena_duel_command($1::jsonb) value',[JSON.stringify(command)])).rows[0].value;
  }
  const command=(action,snapshot,fields={})=>({id:randomUUID(),action,...(snapshot?{matchID:snapshot.id,revision:snapshot.revision}:{}),...fields});
  const send=(who,action,snapshot,fields)=>call(who,command(action,snapshot,fields));
  async function read(who,id) {
    await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[who]);
    return (await db.query('select public.arena_duel_snapshot($1) value',[id])).rows[0].value;
  }
  const hidden=s=> {
    assert(!s.reveal);const wire=JSON.stringify(s);
    for(const key of ['correctNodeID','answerNodeID','trace'])assert(!wire.includes(`"${key}"`));
  };
  await assert.rejects(()=>send('','create',null,{nickname:'Nobody',algorithm:'bfs'}),/unauthenticated/);
  await assert.rejects(()=>send(host,'create',null,{nickname:'Host',algorithm:'invented'}),/invalidAlgorithm/);
  const legacy=JSON.parse(fs.readFileSync(new URL('../content/duel/v1/server/dijkstra.json',import.meta.url)));
  // Simulate an already-running v1 room: no deck, with its original authored question.
  let old=await send(host,'create',null,{nickname:'Legacy',algorithm:'dijkstra'});
  await db.query("update private.duel_rooms set phase='answering' where id=$1",[old.id]);
  assert.deepEqual((await read(host,old.id)).currentRound,legacy[0].round);checks++;
  for(const algorithm of ['bfs','dfs','dijkstra','aStar','greedy']) {
    const bank=JSON.parse(fs.readFileSync(new URL(`../content/duel/v2/server/${algorithm}.json`,import.meta.url)));
    assert.equal(bank.length,24);
    let s=await send(host,'create',null,{nickname:'Host',algorithm});
    const first=await send(guest,'join',null,{nickname:'Guest',code:s.roomCode});s=await read(host,s.id);
    await assert.rejects(()=>read(outsider,s.id),/notMember/);
    await assert.rejects(()=>send(outsider,'join',null,{nickname:'Third',code:s.roomCode}),/roomFull/);
    const seen=[new Set(),new Set(),new Set()];
    // Exercise more rematches than the eight-variant bank: no immediate repetition
    // at exhaustion, and every unseen variant is used before repeating.
    let prior=[];
    for(let match=0;match<10;match++) {
      s=await send(host,'ready',s);s=await send(guest,'ready',s);s=await send(host,'start',s);
      let current=[];
      for(let round=0;round<3;round++) {
        hidden(s);assert.equal(s.phase,'answering');
        const q=bank.find(d=>d.id===s.currentRound.questionID);assert(q);assert.equal(q.slot,round);
        assert.deepEqual(q.round,s.currentRound);current.push(q.id);
        assert.deepEqual((await read(guest,s.id)).currentRound,s.currentRound);
        if(match<8){assert(!seen[round].has(q.id));seen[round].add(q.id);}
        if(prior.length)assert.notEqual(q.id,prior[round]);
        if(round===1){assert(s.currentRound.twist);assert(s.currentRound.previousScenario);assert.equal(s.currentRound.questionKind,'predecessor');}
        const accepted=command('submit',s,{answerNodeID:q.correctNodeID});
        const before=s.players.map(p=>p.score);
        s=await call(host,accepted);hidden(s);assert.deepEqual(s.players.map(p=>p.score),before);
        await assert.rejects(()=>send(guest,'submit',{...s,revision:s.revision-1},{answerNodeID:q.correctNodeID}),/staleRevision/);
        assert.deepEqual(await call(host,accepted),s);
        await assert.rejects(()=>send(host,'submit',s,{answerNodeID:q.correctNodeID}),/alreadySubmitted/);
        const wrong=q.round.choices.find(n=>n!==q.correctNodeID);
        s=await send(guest,'submit',s,{answerNodeID:wrong});
        assert.equal(s.phase,'reveal');assert.equal(s.reveal.correctNodeID,q.correctNodeID);
        assert.deepEqual(s.reveal.trace,q.trace);assert.equal(s.reveal.trace.algorithm,algorithm);
        assert.equal(s.players.find(p=>p.id===host).score,(round+1)*100);
        s=await send(host,'advance',s);s=await send(guest,'advance',s);
      }
      assert.equal(s.phase,'finished');assert.equal(s.players.find(p=>p.id===host).score,300);
      assert.equal(s.players.find(p=>p.id===guest).score,0);prior=current;
      if(match<9)s=await send(host,'rematch',s);
    }
    // New room creation also honours history for both players.
    const recent=(await db.query(`select content_id from private.duel_seen where user_id=$1 order by last_seen desc limit 3`,[host])).rows.map(r=>r.content_id);
    let next=await send(host,'create',null,{nickname:'Host',algorithm});
    next=await send(guest,'join',null,{nickname:'Guest',code:next.roomCode});
    next=await send(host,'ready',next);next=await send(guest,'ready',next);next=await send(host,'start',next);
    assert(!recent.includes(next.currentRound.questionID));
    checks++;console.log(`PASS ${algorithm}: 10 full duels, 30 verified questions, shared privacy gate, stale/duplicate handling, fair scores, anti-repeat exhaustion and new-room history.`);
  }
  // API role can call the checked entry point, but cannot read answer/history/deck tables.
  await db.exec('set role authenticated');
  await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[host]);
  for(const table of ['duel_content','duel_seen','duel_decks']) {
    await assert.rejects(()=>db.query(`select * from private.${table}`),/permission denied/);
  }
  await db.exec('reset role');
  console.log(`PASS: ${checks} groups; legacy compatibility and all five algorithms verified against the full migration chain.`);
} catch(error) {
  console.error('FAIL:',error.message,error.detail ?? '',error.where ?? '');process.exitCode=1;
} finally {await db.close();}
