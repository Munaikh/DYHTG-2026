// Focused end-to-end match smoke test. Node 22+, no npm dependencies.
// Local: provisions one test organiser using the local admin key in memory.
// Hosted development: --remote + ARENA_ORGANISER_TOKEN from an admin-provisioned organiser.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
const remote = process.argv.includes('--remote');
const local = remote ? {} : JSON.parse(execFileSync('supabase', ['status', '-o', 'json'], {encoding:'utf8'}));
const url = process.env.SUPABASE_URL ?? local.API_URL;
const key = process.env.SUPABASE_PUBLISHABLE_KEY ?? local.PUBLISHABLE_KEY ?? local.ANON_KEY;
assert(url && key);
assert(remote || ['127.0.0.1','localhost'].includes(new URL(url).hostname));
assert(!key.startsWith('sb_secret_'));
const course = JSON.parse(readFileSync(new URL('../contracts/v1/courses/gilmorehill-jms-library/candidate-2026-10-17-1/course.json',import.meta.url)));
const bank = (algorithm,slot) => JSON.parse(readFileSync(new URL(`../content/learning/v1/server/${algorithm}/${slot}.json`,import.meta.url)));
async function request(path,token,body,method='POST') {
  const r=await fetch(url+path,{method,headers:{apikey:key,'Content-Type':'application/json',
    ...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  return {ok:r.ok,data:await r.json()};
}
async function ok(path,token,body,method) {
  const r=await request(path,token,body,method); assert(r.ok,JSON.stringify(r.data)); return r.data;
}
const signin=async()=>ok('/auth/v1/signup',null,{});
const [host,guest]=await Promise.all([signin(),signin()]);
let organiser=process.env.ARENA_ORGANISER_TOKEN;
if (!remote) {
  await ok(`/auth/v1/admin/users/${host.user.id}`,local.SERVICE_ROLE_KEY,{app_metadata:{arenaOrganiser:true}},'PUT');
  organiser=host.access_token;
}
assert(organiser,'ARENA_ORGANISER_TOKEN is required for a hosted smoke test.');
let s;
const cmd=(action,entry=false)=>({contractVersion:1,id:randomUUID(),scope:entry?{roomEntry:{}}:
  {match:{matchID:s.room.matchID,course:s.room.course,expectedRevision:s.revision}},action});
async function send(user,command) {
  const receipt=await ok('/rest/v1/rpc/arena_command',user.access_token,{command}); s=receipt.snapshot; return receipt;
}
async function read(user) {return ok('/rest/v1/rpc/arena_snapshot',user.access_token,{match_id:s.room.matchID});}
async function reject(user,command,code) {
  const r=await request('/rest/v1/rpc/arena_command',user.access_token,{command});
  assert(!r.ok);assert.equal(JSON.parse(r.data.message).code,code);
}
async function arrive(user,node,finish=false) {
  const proof=await ok('/rest/v1/rpc/arena_issue_arrival_approval',organiser,
    {match_id:s.room.matchID,player_id:user.user.id,node_id:node});
  const evidence={organiserApproval:{approvalID:proof.approvalID}};
  await send(user,cmd(finish?{finish:{evidence}}:{confirmArrival:{nodeID:node,evidence}}));
}
async function setup(algorithm) {
  await send(host,cmd({createRoom:{nickname:'Host',course:course.reference,algorithm}},true));
  await send(guest,cmd({joinRoom:{code:s.room.roomCode,nickname:'Guest'}},true));
  for (const user of [host,guest]) {
    await send(user,cmd({confirmAlgorithm:{algorithm}})); await send(user,cmd({setReady:{ready:true}}));
  }
}
async function answer(user,algorithm,slot,wrong=false) {
  const doc=bank(algorithm,slot); let answer=doc.correctAnswer;
  if(wrong) answer={cost:{value:99999}};
  const command=cmd({submitAnswer:{challengeID:doc.definition.id,answer}});
  const receipt=await send(user,command);
  // Simulate a lost response and concurrent redelivery with the original UUID.
  const retry=await Promise.all([1,2].map(()=>ok('/rest/v1/rpc/arena_command',user.access_token,{command})));
  retry.forEach(r=>assert.deepEqual(r,receipt));
  await reject(user,cmd({submitAnswer:{challengeID:doc.definition.id,answer}}),'alreadySubmitted');
}
for(const [algorithm,wrongMiddle] of [['dijkstra',false],['aStar',true]]) {
  await setup(algorithm);
  await reject(host,cmd({finish:{evidence:{organiserApproval:{approvalID:'fake'}}}}),'arrivalRequired');
  const evidence={location:{fix:{coordinate:course.nodes[0].coordinate,capturedAt:new Date(Date.now()-60000).toISOString(),horizontalAccuracyMetres:5}}};
  await reject(host,cmd({confirmArrival:{nodeID:course.stops.start,evidence}}),'staleLocation');
  evidence.location.fix.capturedAt=new Date().toISOString();evidence.location.fix.horizontalAccuracyMetres=100;
  await reject(host,cmd({confirmArrival:{nodeID:course.stops.start,evidence}}),'inaccurateLocation');
  await reject(host,cmd({confirmArrival:{nodeID:course.stops.start,evidence:{organiserApproval:{approvalID:'fake'}}}}),'invalidApproval');
  for(const user of [host,guest]) await arrive(user,course.stops.start);
  await send(host,cmd({start:{}}));
  for(const user of [host,guest]) await answer(user,algorithm,'practice');
  await reject(host,cmd({submitAnswer:{challengeID:bank(algorithm,'bonusMiddle').definition.id,answer:{cost:{value:0}}}}),'challengeUnavailable');
  for(const user of [host,guest]) await arrive(user,course.stops.first);
  await answer(host,algorithm,'first');
  assert(s.viewer.feedback.some(f=>f.pending));
  assert.equal(s.room.players.find(p=>p.id===host.user.id).releasedScore,0);
  assert.equal(s.room.players.find(p=>p.id===host.user.id).pendingRewardMaximum,20);
  assert(!JSON.stringify(s.room).includes('correctAnswer'));
  const guestPending=await read(guest);assert.equal(guestPending.viewer.submissions.length,1);
  // The first answer can unlock the next leg while its shared feedback waits.
  await send(host,cmd({chooseRoute:{branch:'standard'}}));
  assert.equal(s.viewer.availableChallenges.length,0);assert(s.viewer.navigation.edgeIDs.length);
  await answer(guest,algorithm,'first');
  const released=await read(host);assert(released.viewer.feedback.every(f=>f.released));
  assert.equal(released.viewer.feedback[1].released.feedback.answers.length,2);
  await send(guest,cmd({chooseRoute:{branch:'bonus'}}));
  await reject(guest,cmd({chooseRoute:{branch:'standard'}}),'routeAlreadyLocked');
  for(const [user,slot,node] of [[host,'standardMiddle',course.stops.standardMiddle],[guest,'bonusMiddle',course.stops.bonusMiddle]]) {
    await arrive(user,node);assert.equal(s.viewer.availableChallenges[0].slot,slot);
    await answer(user,algorithm,slot,wrongMiddle);
    assert.equal(s.viewer.feedback.at(-1).released.feedback.answers.length,1);
    await arrive(user,course.stops.third);await answer(user,algorithm,'third');
  }
  for(const user of [host,guest]) await arrive(user,course.stops.finish,true);
  const first=await read(host),second=await read(guest);
  assert.deepEqual(first.room,second.room);assert.equal(first.room.phase,'finished');
  const standings=Object.values(first.room.result)[0].standings;
  assert.deepEqual(standings.map(p=>p.score),wrongMiddle?[60,60]:[80,100]);
  assert(wrongMiddle?first.room.result.draw:first.room.result.winner.playerID===guest.user.id);
  await answer(host,algorithm,'learningCheck');
  assert.equal(s.viewer.learningCheck.nodeCorrect,true);assert.equal(s.viewer.learningCheck.reasonCorrect,true);
  assert.deepEqual(Object.values(s.room.result)[0].standings,standings);
  if(process.env.ARENA_MATCH_WIRE_OUTPUT) writeFileSync(process.env.ARENA_MATCH_WIRE_OUTPUT,JSON.stringify(s));
  console.log(`ok - ${algorithm}: gated feedback, locked routes, retries, ${standings.map(p=>p.score).join('/')}, learning check`);
}
await setup('dijkstra');await send(guest,cmd({leave:{}}));
assert.equal(s.room.phase,'incomplete');assert.equal(s.room.result.incomplete.departedPlayerID,guest.user.id);
const restored=await read(host);assert.deepEqual(restored.room,s.room);
await reject(host,cmd({start:{}}),'invalidPhase');
console.log('ok - explicit departure is incomplete; snapshot restoration preserves authoritative state');
