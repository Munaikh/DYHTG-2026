// End-to-end match reliability tests. Node 22+, no npm dependencies.
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
if (key.split('.').length === 3) {
  assert.equal(JSON.parse(Buffer.from(key.split('.')[1], 'base64url')).role, 'anon');
}
const course = JSON.parse(readFileSync(new URL('../contracts/v1/courses/gilmorehill-jms-library/candidate-2026-10-17-1/course.json',import.meta.url)));
const bank = (algorithm,slot) => JSON.parse(readFileSync(new URL(`../content/learning/v1/server/${algorithm}/${slot}.json`,import.meta.url)));
// Token-free wire corpus for the independent Swift decoder test.
const wire = { receipts: [], snapshots: [], errors: [], reconnects: [] };
const query = sql => JSON.parse(execFileSync('supabase', ['db', 'query', '--local', '-o', 'json', sql],
  { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 })).rows;
if (!remote) {
  const documents = query('select algorithm, slot, document from private.arena_challenges');
  assert.equal(documents.length, 12);
  for (const row of documents) assert.deepEqual(row.document, bank(row.algorithm, row.slot));
  const registered = query('select definition from private.arena_courses');
  assert.deepEqual(registered.map(row => row.definition), [course]);
  console.log('ok - deployed course and all 12 private documents match Swift-exported fixtures');
}
async function request(path,token,body,method='POST') {
  const r=await fetch(url+path,{method,headers:{apikey:key,'Content-Type':'application/json',
    ...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  return {ok:r.ok,data:await r.json()};
}
async function ok(path,token,body,method) {
  const r=await request(path,token,body,method); assert(r.ok,JSON.stringify(r.data)); return r.data;
}
const signin=async()=>ok('/auth/v1/signup',null,{});
const [host,guest,outsider]=await Promise.all([signin(),signin(),signin()]);
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
  const receipt=await ok('/rest/v1/rpc/arena_command',user.access_token,{command});
  wire.receipts.push(receipt); s=receipt.snapshot; return receipt;
}
async function read(user) {
  const snapshot=await ok('/rest/v1/rpc/arena_snapshot',user.access_token,{match_id:s.room.matchID});
  wire.snapshots.push(snapshot); return snapshot;
}
function errorCode(r,code) {
  assert(!r.ok, `Expected ${code}`);
  assert.equal(r.data.code,'P0001');
  const error=JSON.parse(r.data.message); assert.equal(error.code,code);
  wire.errors.push(error); return error;
}
async function reject(user,command,code) {
  const r=await request('/rest/v1/rpc/arena_command',user.access_token,{command});
  return errorCode(r,code);
}
async function arrivalCommand(user,node,finish=false) {
  const proof=await ok('/rest/v1/rpc/arena_issue_arrival_approval',organiser,
    {match_id:s.room.matchID,player_id:user.user.id,node_id:node});
  const evidence={organiserApproval:{approvalID:proof.approvalID}};
  return cmd(finish?{finish:{evidence}}:{confirmArrival:{nodeID:node,evidence}});
}
async function arrive(user,node,finish=false) { await send(user,await arrivalCommand(user,node,finish)); }
// Distinct commands race at one revision: exactly one commits. Reconcile the
// other player's legitimate action against the new revision when requested.
async function race(entries,reconcile=false) {
  const revision=s.revision;
  const results=await Promise.all(entries.map(([user,command]) =>
    request('/rest/v1/rpc/arena_command',user.access_token,{command})));
  assert.equal(results.filter(r=>r.ok).length,1);
  const winner=results.findIndex(r=>r.ok), loser=1-winner;
  s=results[winner].data.snapshot; wire.receipts.push(results[winner].data);
  assert.equal(s.revision,revision+1);
  assert.equal(errorCode(results[loser],'staleRevision').currentRevision,s.revision);
  if (reconcile) {
    const [user,command]=entries[loser];
    await send(user,{...command,scope:cmd(command.action).scope});
  }
  for (const [i,[user,command]] of entries.entries()) {
    if (i!==winner && !reconcile) continue;
    const accepted=i===winner?command:{...command,scope:{match:{...command.scope.match,expectedRevision:revision+1}}};
    const retried=await ok('/rest/v1/rpc/arena_command',user.access_token,{command:accepted});
    assert.equal(retried.acceptedRevision,revision+(i===winner?1:2));
  }
  assert.equal((await read(host)).revision,revision+(reconcile?2:1));
}
async function setup(algorithm) {
  await send(host,cmd({createRoom:{nickname:'Host',course:course.reference,algorithm}},true));
  await send(guest,cmd({joinRoom:{code:s.room.roomCode,nickname:'Guest'}},true));
  for (const user of [host,guest]) {
    await send(user,cmd({confirmAlgorithm:{algorithm}})); await send(user,cmd({setReady:{ready:true}}));
  }
}
function answerCommand(algorithm,slot,wrong=false) {
  const doc=bank(algorithm,slot); let answer=doc.correctAnswer;
  if(wrong) answer=doc.correctAnswer.node
    ? {node:{nodeID:doc.definition.action.selectNode.options.find(n=>n!==doc.correctAnswer.node.nodeID)}}
    : {cost:{value:99999}};
  return cmd({submitAnswer:{challengeID:doc.definition.id,answer}});
}
async function answer(user,algorithm,slot,wrong=false) {
  const command=answerCommand(algorithm,slot,wrong);
  const {challengeID}=command.action.submitAnswer;
  // Race different UUIDs too, so database first-submission rules are exercised.
  const duplicate={...command,id:randomUUID()};
  await race([[user,command],[user,duplicate]]);
  const accepted=s.viewer.submissions.find(a=>a.challengeID===challengeID);
  const saved=accepted.commandID===command.id?command:duplicate;
  const receipt=await ok('/rest/v1/rpc/arena_command',user.access_token,{command:saved});
  // Simulate a lost response and concurrent redelivery with the original UUID.
  const retry=await Promise.all([1,2].map(()=>ok('/rest/v1/rpc/arena_command',user.access_token,{command:saved})));
  retry.forEach(r=>assert.deepEqual(r,receipt));
  await reject(user,cmd(command.action),'alreadySubmitted');
  return saved;
}
for(const [algorithm,wrongMiddle] of [['dijkstra',false],['aStar',true]]) {
  await setup(algorithm);
  const mismatch=cmd({start:{}}); mismatch.scope.match.course={...course.reference,version:'unknown'};
  await reject(host,mismatch,'incompatibleCourse');
  const beforeDenied=s.revision;
  for (const action of [{start:{}},{chooseRoute:{branch:'bonus'}},
    {submitAnswer:{challengeID:bank(algorithm,'first').definition.id,answer:bank(algorithm,'first').correctAnswer}},
    {finish:{evidence:{organiserApproval:{approvalID:'fake'}}}},{leave:{}}]) {
    const denied=await reject(outsider,cmd(action),'notMember');
    assert.equal(denied.currentRevision,undefined);
  }
  errorCode(await request('/rest/v1/rpc/arena_snapshot',outsider.access_token,
    {match_id:s.room.matchID}),'notMember');
  errorCode(await request('/rest/v1/rpc/arena_issue_arrival_approval',outsider.access_token,
    {match_id:s.room.matchID,player_id:host.user.id,node_id:course.stops.start}),'invalidApproval');
  assert.equal((await read(host)).revision,beforeDenied);
  await reject(host,cmd({finish:{evidence:{organiserApproval:{approvalID:'fake'}}}}),'arrivalRequired');
  const evidence={location:{fix:{coordinate:course.nodes[0].coordinate,capturedAt:new Date(Date.now()-60000).toISOString(),horizontalAccuracyMetres:5}}};
  await reject(host,cmd({confirmArrival:{nodeID:course.stops.start,evidence}}),'staleLocation');
  evidence.location.fix.capturedAt=new Date().toISOString();evidence.location.fix.horizontalAccuracyMetres=100;
  await reject(host,cmd({confirmArrival:{nodeID:course.stops.start,evidence}}),'inaccurateLocation');
  await reject(host,cmd({confirmArrival:{nodeID:course.stops.start,evidence:{organiserApproval:{approvalID:'fake'}}}}),'invalidApproval');
  for(const user of [host,guest]) await arrive(user,course.stops.start);
  await race([[host,cmd({start:{}})],[host,cmd({start:{}})]]);
  assert.equal(s.room.phase,'practice');
  for(const user of [host,guest]) await answer(user,algorithm,'practice');
  await reject(host,cmd({submitAnswer:{challengeID:bank(algorithm,'bonusMiddle').definition.id,answer:{cost:{value:0}}}}),'challengeUnavailable');
  for(const user of [host,guest]) await arrive(user,course.stops.first);
  // Serialize before sending, as a relaunched client would. Deliberately discard
  // the receipt; recovery below only has this saved command and old snapshot.
  const persisted=JSON.parse(JSON.stringify({lastConfirmedSnapshot:await read(host),
    pendingCommand:answerCommand(algorithm,'first',wrongMiddle)}));
  wire.reconnects.push(persisted);
  await send(host,persisted.pendingCommand);
  assert(s.viewer.feedback.some(f=>f.pending));
  assert.equal(s.room.players.find(p=>p.id===host.user.id).releasedScore,0);
  assert.equal(s.room.players.find(p=>p.id===host.user.id).pendingRewardMaximum,20);
  assert(!JSON.stringify(s.room).includes('correctAnswer'));
  const guestPending=await read(guest);assert.equal(guestPending.viewer.submissions.length,1);
  errorCode(await request('/rest/v1/rpc/arena_snapshot',outsider.access_token,
    {match_id:s.room.matchID}),'notMember');
  assert(!guestPending.viewer.feedback.some(f=>f.released?.feedback.challengeID===bank(algorithm,'first').definition.id));
  assert.deepEqual(s.viewer.feedback.find(f=>f.pending),{pending:{challengeID:bank(algorithm,'first').definition.id}});
  assert(!JSON.stringify(s.room).includes('isCorrect'));
  assert(!JSON.stringify(s.room).includes('explanation'));
  // The first answer can unlock the next leg while its shared feedback waits.
  await race([[host,cmd({chooseRoute:{branch:'standard'}})],[host,cmd({chooseRoute:{branch:'standard'}})]]);
  assert.equal(s.viewer.availableChallenges.length,0);assert(s.viewer.navigation.edgeIDs.length);
  await reject(host,cmd({chooseRoute:{branch:'bonus'}}),'routeAlreadyLocked');
  await answer(guest,algorithm,'first',wrongMiddle);
  const released=await read(host);assert(released.viewer.feedback.every(f=>f.released));
  assert.equal(released.viewer.feedback[1].released.feedback.answers.length,2);
  assert.equal(released.viewer.feedback[1].released.feedback.answers[0].isCorrect,!wrongMiddle);
  // Relaunch with the SAME restored Auth identity. An uncertain old command
  // returns its original (older, pending) receipt, never a second reward.
  const refresh=await ok('/auth/v1/token?grant_type=refresh_token',null,{refresh_token:host.refresh_token});
  assert.equal(refresh.user.id,host.user.id); Object.assign(host,refresh);
  const old=await ok('/rest/v1/rpc/arena_command',host.access_token,{command:persisted.pendingCommand});
  assert(old.snapshot.revision<released.revision);
  const restored=await read(host);
  assert.deepEqual(restored.room,released.room); assert.equal(restored.revision,released.revision);
  assert(restored.revision>persisted.lastConfirmedSnapshot.revision);
  assert.equal(restored.viewer.submissions.filter(a=>a.commandID===persisted.pendingCommand.id).length,1);
  assert.equal(restored.room.phase,'active'); s=restored;
  wire.receipts.push(old);
  await send(guest,cmd({chooseRoute:{branch:'bonus'}}));
  await reject(guest,cmd({chooseRoute:{branch:'standard'}}),'routeAlreadyLocked');
  for(const [user,slot,node] of [[host,'standardMiddle',course.stops.standardMiddle],[guest,'bonusMiddle',course.stops.bonusMiddle]]) {
    await arrive(user,node);assert.equal(s.viewer.availableChallenges[0].slot,slot);
    await answer(user,algorithm,slot,wrongMiddle);
    assert.equal(s.viewer.feedback.at(-1).released.feedback.answers.length,1);
    await arrive(user,course.stops.third);
  }
  const third=bank(algorithm,'third');
  await race([host,guest].map(user=>[user,cmd({submitAnswer:{challengeID:third.definition.id,answer:third.correctAnswer}})]),true);
  const finishCommands=[];
  for(const user of [host,guest]) finishCommands.push([user,await arrivalCommand(user,course.stops.finish,true)]);
  await race(finishCommands,true);
  const first=await read(host),second=await read(guest);
  assert.deepEqual(first.room,second.room);assert.equal(first.room.phase,'finished');
  const standings=Object.values(first.room.result)[0].standings;
  assert.deepEqual(standings.map(p=>p.score),wrongMiddle?[40,40]:[80,100]);
  for (const standing of standings) {
    assert.equal(standing.awards.length,4);
    assert.equal(standing.awards.filter(a=>a.slot===undefined && a.points===20).length,1);
  }
  assert(wrongMiddle?first.room.result.draw:first.room.result.winner.playerID===guest.user.id);
  await answer(host,algorithm,'learningCheck');
  assert.equal(s.viewer.learningCheck.nodeCorrect,true);assert.equal(s.viewer.learningCheck.reasonCorrect,true);
  assert.deepEqual(Object.values(s.room.result)[0].standings,standings);
  console.log(`ok - ${algorithm}: concurrent start/route/answer/finish, private delayed feedback, restored session, ${standings.map(p=>p.score).join('/')}, learning check`);
}
await setup('dijkstra');
for(const user of [host,guest]) await arrive(user,course.stops.start);
await send(host,cmd({start:{}}));
for(const user of [host,guest]) await answer(user,'dijkstra','practice');
await arrive(host,course.stops.first); await answer(host,'dijkstra','first');
await send(guest,cmd({leave:{}}));
assert.equal(s.room.phase,'incomplete');assert.equal(s.room.result.incomplete.departedPlayerID,guest.user.id);
const restored=await read(host);assert.deepEqual(restored.room,s.room);
assert.equal(restored.room.players.find(p=>p.id===host.user.id).releasedScore,0);
assert.deepEqual(restored.room.result.incomplete.standings.find(p=>p.playerID===host.user.id).awards,[]);
assert.deepEqual(restored.viewer.feedback.at(-1),{pending:{challengeID:bank('dijkstra','first').definition.id}});
await reject(host,cmd({start:{}}),'invalidPhase');
for (const snapshot of [...wire.snapshots,...wire.receipts.map(r=>r.snapshot)]) {
  for (const challenge of snapshot.viewer.availableChallenges) {
    assert.deepEqual(challenge,bank(snapshot.room.algorithm,challenge.slot).definition);
  }
  for (const feedback of snapshot.viewer.feedback) {
    if (feedback.pending) {
      assert.deepEqual(Object.keys(feedback.pending),['challengeID']);
      continue;
    }
    const actual=feedback.released.feedback;
    const doc=['practice','first','standardMiddle','bonusMiddle','third','learningCheck']
      .map(slot=>bank(snapshot.room.algorithm,slot)).find(d=>d.definition.id===actual.challengeID);
    assert(doc);
    for (const field of ['correctAnswer','explanation','workedSteps','workedStepTraceIndices','trace']) {
      assert.deepEqual(actual[field],doc[field]);
    }
  }
}
if(process.env.ARENA_MATCH_WIRE_OUTPUT) writeFileSync(process.env.ARENA_MATCH_WIRE_OUTPUT,JSON.stringify(wire));
console.log('ok - explicit departure is incomplete; unreleased answers/rewards stay private after restoration');
