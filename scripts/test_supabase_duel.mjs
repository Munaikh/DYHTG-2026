// Node 22+. Real Auth + PostgREST contract tests. Only publishable keys and anonymous sessions.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const remote = process.argv.includes('--remote');
const config = remote ? JSON.parse(readFileSync(new URL('../supabase/client-config.json',import.meta.url))) :
  JSON.parse(execFileSync('/opt/homebrew/bin/supabase',['status','-o','json'],{encoding:'utf8'}));
const url = process.env.SUPABASE_URL ?? config.url ?? config.API_URL;
const key = process.env.SUPABASE_PUBLISHABLE_KEY ?? config.publishableKey ?? config.PUBLISHABLE_KEY;
assert(url && key && !key.startsWith('sb_secret_'));
assert(remote || ['127.0.0.1','localhost'].includes(new URL(url).hostname));
const wire = {snapshots: [], errors: []};
let checks=0;
const passed = name => console.log(`ok ${++checks} - ${name}`);
async function request(path,token,body,extra={}) {
  const response=await fetch(url+path,{method:body===undefined?'GET':'POST',headers:{apikey:key,
    'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`} :{}),...extra},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(15000)});
  const text=await response.text(); return {ok:response.ok,status:response.status,data:text?JSON.parse(text):null};
}
async function ok(path,token,body) { const r=await request(path,token,body); assert(r.ok,JSON.stringify(r.data)); return r.data; }
const cmd=(action,s,more={})=>({id:randomUUID(),action,...(s?{matchID:s.id,revision:s.revision}:{}),...more});
const raw=(user,command)=>request('/rest/v1/rpc/arena_duel_command',user?.access_token,{command});
async function send(user,command) {const r=await raw(user,command);assert(r.ok,JSON.stringify(r.data));wire.snapshots.push(r.data);return r.data;}
async function read(user,s){const result=await ok('/rest/v1/rpc/arena_duel_snapshot',user.access_token,{match_id:s.id});wire.snapshots.push(result);return result;}
function fail(result,code) {
  assert(!result.ok,`Expected ${code}`); wire.errors.push(result.data);
  assert.equal(JSON.parse(result.data.message).code,code,JSON.stringify(result.data));
}
function hidden(s) {
  assert(!s.reveal); assert(!JSON.stringify(s).includes('correctNodeID')); assert(!JSON.stringify(s).includes('"trace"'));
  assert(!JSON.stringify(s).includes('"answerNodeID"'));
}
const [host,guest,outsider]=await Promise.all(Array.from({length:3},()=>ok('/auth/v1/signup',null,{})));
assert(host.user.is_anonymous && guest.user.is_anonymous);
passed('three independent real anonymous auth identities');
assert(!(await raw(null,cmd('create',null,{nickname:'No session',algorithm:'dijkstra'}))).ok);
passed('unauthenticated command denied');
for(const table of ['duel_rounds','duel_answers','duel_receipts','duel_players']){
  const publicRead=await request(`/rest/v1/${table}?select=*`,host.access_token);
  assert(!publicRead.ok);
  const privateRead=await request(`/rest/v1/${table}?select=*`,host.access_token,undefined,{'Accept-Profile':'private'});
  assert(!privateRead.ok);
}
passed('answer bank, private predictions, receipts and player tables are not directly exposed');
for(const algorithm of ['dijkstra','aStar']) {
  const bank=JSON.parse(readFileSync(new URL(`../content/duel/v1/server/${algorithm}.json`,import.meta.url)));
  const create=cmd('create',null,{nickname:'Duel test host',algorithm});
  let s=await send(host,create); assert.equal(s.phase,'lobby');assert(!s.currentRound);hidden(s);
  assert.deepEqual(await send(host,create),s);
  fail(await raw(host,{...create,nickname:'Changed'}),'commandConflict');
  passed(`${algorithm}: duplicate create exactly once; conflicting reuse denied`);
  fail(await raw(host,cmd('start',s)),'notReady');
  let guestView=await send(guest,cmd('join',null,{nickname:'Duel test guest',code:s.roomCode.toLowerCase()}));
  assert.equal(guestView.viewerID,guest.user.id);assert.equal(guestView.players.length,2);
  fail(await raw(outsider,cmd('join',null,{nickname:'Third',code:s.roomCode})),'roomFull');
  fail(await request('/rest/v1/rpc/arena_duel_snapshot',outsider.access_token,{match_id:s.id}),'notMember');
  fail(await raw(outsider,cmd('leave',guestView)),'notMember');
  fail(await raw(host,cmd('ready',s)),'staleRevision');
  s=await read(host,s);
  fail(await raw(guest,cmd('start',s)),'hostOnly');
  s=await send(host,cmd('ready',s));s=await send(guest,cmd('ready',s));s=await send(host,cmd('start',s));
  passed(`${algorithm}: capacity, membership, stale state, readiness and host start enforced`);
  for(let round=0;round<3;round++) {
    assert.equal(s.phase,'answering');assert.equal(s.roundIndex,round);hidden(s);
    assert.deepEqual(s.currentRound,bank[round].round);
    if(round===1){assert(s.currentRound.twist);assert(s.currentRound.previousScenario);}
    fail(await raw(host,cmd('submit',s,{answerNodeID:'not-a-choice'})),'invalidAnswer');
    fail(await raw(host,cmd('advance',s)),'invalidPhase');
    const correct=bank[round].correctNodeID;
    const wrong=bank[round].round.choices.find(x=>x!==correct);
    const hostPick=algorithm==='aStar'&&round===1?wrong:correct;
    const hostCommand=cmd('submit',s,{answerNodeID:hostPick});
    const guestCommand=cmd('submit',s,{answerNodeID:wrong});
    // Two real requests race from the same revision. One commits, one must refresh.
    const raced=await Promise.all([raw(host,hostCommand),raw(guest,guestCommand)]);
    assert.equal(raced.filter(x=>x.ok).length,1);
    const firstIndex=raced.findIndex(x=>x.ok), firstUser=firstIndex===0?host:guest;
    const firstCommand=firstIndex===0?hostCommand:guestCommand;
    const loser=firstIndex===0?guest:host; const loserPick=firstIndex===0?wrong:hostPick;
    fail(raced[1-firstIndex],'staleRevision');
    const first=raced[firstIndex].data;wire.snapshots.push(first);hidden(first);
    assert.equal(first.players.filter(x=>x.submitted).length,1);
    const previousScores=first.players.map(p=>p.score);
    assert.deepEqual((await read(loser,s)).players.map(p=>p.score),previousScores);
    hidden(await read(loser,s));
    assert.deepEqual(await send(firstUser,firstCommand),first);
    fail(await raw(firstUser,cmd('submit',first,{answerNodeID:wrong})),'alreadySubmitted');
    s=await send(loser,cmd('submit',first,{answerNodeID:loserPick}));
    assert.equal(s.phase,'reveal');assert.equal(s.reveal.correctNodeID,correct);
    assert.deepEqual(s.reveal.trace,bank[round].trace);
    assert.equal(s.reveal.answers.length,2);
    assert.equal(s.reveal.answers.find(x=>x.playerID===host.user.id).points,hostPick===correct?100:0);
    assert.equal(s.reveal.answers.find(x=>x.playerID===guest.user.id).points,0);
    const revealed=s;
    // Retrying an old accepted command cannot award points twice.
    assert.deepEqual(await send(firstUser,firstCommand),first);
    s=await read(host,s);assert.deepEqual(s.players.map(x=>x.score),revealed.players.map(x=>x.score));
    const reconnected=await ok('/auth/v1/token?grant_type=refresh_token',null,{refresh_token:guest.refresh_token});
    Object.assign(guest,reconnected);
    const recovered=await read(guest,s);assert.equal(recovered.phase,'reveal');assert.deepEqual(recovered.reveal,s.reveal);
    s=await send(host,cmd('advance',s));assert.equal(s.phase,'reveal');
    s=await send(guest,cmd('advance',s));
    passed(`${algorithm} round ${round+1}: concurrent submissions, hidden answers/scores, exact scoring, refresh-session reconnect, shared reveal and mutual advance`);
  }
  assert.equal(s.phase,'finished');
  assert.equal(s.players.find(x=>x.id===host.user.id).score,algorithm==='dijkstra'?300:200);
  assert.equal(s.players.find(x=>x.id===guest.user.id).score,0);
  const hostResult=await read(host,s),guestResult=await read(guest,s);
  assert.deepEqual({...hostResult,viewerID:null},{...guestResult,viewerID:null});
  fail(await raw(guest,cmd('rematch',s)),'hostOnly');
  s=await send(host,cmd('rematch',s));assert.equal(s.phase,'lobby');assert(s.players.every(p=>p.score===0&&!p.ready&&!p.submitted));hidden(s);
  s=await send(host,cmd('ready',s));s=await send(guest,cmd('ready',s));s=await send(host,cmd('start',s));
  s=await send(guest,cmd('leave',s));assert.equal(s.phase,'incomplete');
  fail(await raw(host,cmd('submit',s,{answerNodeID:'A'})),'invalidPhase');
  assert.equal((await read(host,s)).phase,'incomplete');
  passed(`${algorithm}: matching final scores, clean rematch, explicit leave marks both players incomplete`);
}
const output=process.env.DUEL_WIRE_PATH ?? '/tmp/duel-wire.json';
writeFileSync(output,JSON.stringify(wire,null,2));
console.log(`PASS ${checks} checks; token-free wire corpus: ${output}`);
