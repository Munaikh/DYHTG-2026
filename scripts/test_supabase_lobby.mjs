// Node 22+; built-in fetch/WebSocket only. Credentials stay in memory.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

let url = process.env.SUPABASE_URL;
let key = process.env.SUPABASE_PUBLISHABLE_KEY;
if (!url || !key) {
  const local = JSON.parse(execFileSync('supabase', ['status', '-o', 'json'], { encoding: 'utf8' }));
  url ??= local.API_URL;
  key ??= local.PUBLISHABLE_KEY ?? local.ANON_KEY;
}
assert(url && key, 'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.');
assert(!key.startsWith('sb_secret_'), 'Use a publishable key, never a secret key.');
if (key.split('.').length === 3) {
  assert.equal(JSON.parse(Buffer.from(key.split('.')[1], 'base64url')).role, 'anon');
}
assert(process.argv.includes('--remote') || ['127.0.0.1', 'localhost'].includes(new URL(url).hostname),
  'Remote tests create anonymous test users and rooms; pass --remote explicitly.');
const course = { id: 'gilmorehill-jms-library', version: 'candidate-2026-10-17-1' };
let checks = 0;
const passed = (name) => { checks++; console.log(`ok ${checks} - ${name}`); };
async function request(path, token, body, method = body === undefined ? 'GET' : 'POST', extra = {}) {
  const response = await fetch(`${url}${path}`, {
    method, headers: { apikey: key, ...(token ? { Authorization: `Bearer ${token}` } : {}),
      'Content-Type': 'application/json', ...extra },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(15000)
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  return { status: response.status, ok: response.ok, data };
}
async function signIn() {
  const r = await request('/auth/v1/signup', null, {});
  assert(r.ok, `Anonymous sign-in failed (${r.status}); enable anonymous auth and check its rate limit.`);
  assert(r.data.user.is_anonymous);
  return r.data;
}
function command(action, scope = { roomEntry: {} }) {
  return { contractVersion: 1, id: randomUUID(), scope, action };
}
function scoped(snapshot, action) {
  return command(action, { match: { matchID: snapshot.room.matchID, course: snapshot.room.course,
    expectedRevision: snapshot.revision } });
}
async function send(session, cmd) {
  return request('/rest/v1/rpc/arena_command', session.access_token, { command: cmd });
}
async function accept(session, cmd) {
  const r = await send(session, cmd);
  assert(r.ok, `Command failed: ${JSON.stringify(r.data)}`);
  assert.equal(r.data.commandID.toLowerCase(), cmd.id.toLowerCase());
  assert.equal(r.data.acceptedRevision, r.data.snapshot.revision);
  assert.equal(r.data.snapshot.viewer.playerID, session.user.id);
  return r.data;
}
function errorCode(r, expected) {
  assert(!r.ok, `Expected ${expected}, received success.`);
  assert.equal(r.data.code, 'P0001');
  const error = JSON.parse(r.data.message);
  assert.equal(error.code, expected);
  return error;
}
async function snapshot(session, matchID) {
  const r = await request('/rest/v1/rpc/arena_snapshot', session.access_token, { match_id: matchID });
  assert(r.ok, `Snapshot failed: ${JSON.stringify(r.data)}`);
  assert.equal(r.data.viewer.playerID, session.user.id);
  return r.data;
}
async function makeRoom(session, algorithm = 'dijkstra') {
  const cmd = command({ createRoom: { nickname: 'Host', course, algorithm } });
  return { cmd, receipt: await accept(session, cmd) };
}

// Phoenix protocol subscription using Node's built-in WebSocket. Only safe
// invalidations may arrive; a non-member must receive none for the target room.
async function subscribe(session, matchID) {
  const wsURL = new URL('/realtime/v1/websocket', url);
  wsURL.protocol = wsURL.protocol === 'https:' ? 'wss:' : 'ws:';
  wsURL.searchParams.set('apikey', key);
  wsURL.searchParams.set('vsn', '1.0.0');
  const ws = new WebSocket(wsURL);
  const events = [];
  const topic = `realtime:arena-test-${randomUUID()}`;
  let resolveJoin, rejectJoin;
  const joined = new Promise((resolve, reject) => { resolveJoin = resolve; rejectJoin = reject; });
  const timeout = setTimeout(() => rejectJoin(new Error('Realtime subscription timed out')), 15000);
  ws.addEventListener('error', () => rejectJoin(new Error('Realtime connection failed')));
  ws.addEventListener('message', ({ data }) => {
    const event = JSON.parse(data);
    if (event.event === 'phx_reply' && event.ref === '1' && event.payload.status !== 'ok') {
      rejectJoin(new Error('Realtime join rejected'));
    }
    if (event.event === 'system' && event.payload.extension === 'postgres_changes') {
      if (event.payload.status === 'ok') resolveJoin();
      else rejectJoin(new Error(`Realtime subscription failed: ${event.payload.message}`));
    }
    if (event.event === 'postgres_changes') events.push(event.payload.data);
  });
  ws.addEventListener('open', () => ws.send(JSON.stringify({ topic, event: 'phx_join', ref: '1',
    payload: { access_token: session.access_token, config: { broadcast: { self: false },
      presence: { key: '' }, postgres_changes: [{ event: '*', schema: 'public',
        table: 'arena_invalidations', filter: `matchID=eq.${matchID}` }] } } })));
  try { await joined; } catch (error) { ws.close(); throw error; } finally { clearTimeout(timeout); }
  return { events, close: () => ws.close() };
}

async function run() {
  const [host, guest, outsider] = await Promise.all([signIn(), signIn(), signIn()]);
  assert.equal(new Set([host.user.id, guest.user.id, outsider.user.id]).size, 3);
  if (process.env.ARENA_TEST_IDENTITIES_OUTPUT) writeFileSync(process.env.ARENA_TEST_IDENTITIES_OUTPUT,
    JSON.stringify([host.user.id, guest.user.id, outsider.user.id]));
  const refresh = await request('/auth/v1/token?grant_type=refresh_token', null,
    { refresh_token: host.refresh_token });
  assert(refresh.ok); assert.equal(refresh.data.user.id, host.user.id);
  Object.assign(host, refresh.data);
  passed('distinct anonymous identities survive session restoration with a refresh token');

  const { cmd: create, receipt: created } = await makeRoom(host);
  let s = created.snapshot;
  const matchID = s.room.matchID;
  assert.match(s.room.roomCode, /^[0-9A-F]{10}$/);
  assert.equal(s.room.creatorID, host.user.id);
  assert.equal(s.room.players.length, 1);
  assert.equal(s.revision, 1);
  assert.deepEqual(await accept(host, create), created);
  passed('create retry returns the original receipt and only one room/player');
  errorCode(await request('/rest/v1/rpc/arena_snapshot', guest.access_token, { match_id: matchID }), 'notMember');
  const noAuth = await request('/rest/v1/rpc/arena_command', null, { command: create });
  assert(!noAuth.ok);
  passed('anonymous API role and non-member sessions cannot access room RPCs');
  for (const code of ['bad', '0000000000']) {
    errorCode(await send(guest, command({ joinRoom: { code, nickname: 'Guest' } })), 'roomNotFound');
  }
  const join = command({ joinRoom: { code: ` ${s.room.roomCode.toLowerCase()} `, nickname: 'Guest' } });
  const joined = await accept(guest, join);
  s = joined.snapshot;
  assert.equal(s.room.players.length, 2);
  assert.equal(s.revision, 2);
  assert.deepEqual(await accept(guest, join), joined);
  const rejoin = await accept(guest, command({ joinRoom: { code: s.room.roomCode, nickname: 'Guest' } }));
  assert.equal(rejoin.acceptedRevision, 2);
  errorCode(await send(outsider, command({ joinRoom: { code: s.room.roomCode, nickname: 'Third' } })), 'roomFull');
  passed('case-insensitive join is idempotent; invalid codes and a third player fail clearly');

  errorCode(await send(outsider, scoped(s, { setReady: { ready: true } })), 'notMember');
  errorCode(await send(guest, scoped(s, { selectAlgorithm: { algorithm: 'aStar' } })), 'invalidCommand');
  errorCode(await send(guest, scoped(s, { setReady: { ready: true } })), 'algorithmNotConfirmed');
  errorCode(await send(guest, scoped(s, { confirmAlgorithm: { algorithm: 'aStar' } })), 'algorithmNotConfirmed');
  errorCode(await send(host, scoped(s, { start: {} })), 'algorithmNotConfirmed');
  passed('membership, creator-only changes, confirmation and start prerequisites are enforced');

  const confirmation = scoped(s, { confirmAlgorithm: { algorithm: 'dijkstra' } });
  const confirmed = await accept(host, confirmation);
  s = confirmed.snapshot;
  s = (await accept(guest, scoped(s, { confirmAlgorithm: { algorithm: 'dijkstra' } }))).snapshot;
  const ready = scoped(s, { setReady: { ready: true } });
  const readyReceipt = await accept(host, ready);
  s = readyReceipt.snapshot;
  s = (await accept(guest, scoped(s, { setReady: { ready: true } }))).snapshot;
  assert(s.room.players.every(p => p.ready && p.algorithmConfirmed));
  errorCode(await send(host, scoped(s, { start: {} })), 'arrivalRequired');
  assert(s.room.players.every(p => p.arrivals.length === 0));
  assert.deepEqual(await accept(host, confirmation), confirmed);
  assert.deepEqual(await accept(host, ready), readyReceipt);
  assert.deepEqual(await accept(host, create), created);
  assert.deepEqual(await accept(guest, join), joined);
  errorCode(await send(host, { ...ready, action: { setReady: { ready: false } } }), 'idempotencyConflict');
  const stale = errorCode(await send(host, scoped(created.snapshot, { setReady: { ready: false } })), 'staleRevision');
  assert.equal(stale.currentRevision, s.revision);
  passed('ready/create/join retries survive stale revisions; changed payloads conflict; start requires verified arrival');

  const memberChannel = await subscribe(host, matchID);
  const outsiderChannel = await subscribe(outsider, matchID);
  try {
    s = (await accept(host, scoped(s, { selectAlgorithm: { algorithm: 'aStar' } }))).snapshot;
    assert(s.room.players.every(p => !p.ready && !p.algorithmConfirmed));
    const deadline = Date.now() + 10000;
    while (!memberChannel.events.some(e => e.record?.revision === s.revision) && Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert(memberChannel.events.some(e => e.record?.revision === s.revision), 'Member did not receive invalidation');
    await new Promise(resolve => setTimeout(resolve, 300));
    assert.equal(outsiderChannel.events.length, 0);
    for (const e of memberChannel.events) {
      assert.deepEqual(Object.keys(e.record).sort(), ['matchID', 'revision']);
      assert.equal(e.record.matchID, matchID);
    }
  } finally { memberChannel.close(); outsiderChannel.close(); }
  passed('algorithm changes clear both players; real Realtime events contain only ID/revision and obey membership RLS');

  const rows = await request('/rest/v1/arena_invalidations?select=*', host.access_token);
  assert(rows.ok); assert(rows.data.some(row => row.matchID === matchID));
  assert(rows.data.every(row => Object.keys(row).sort().join(',') === 'matchID,revision'));
  const hidden = await request(`/rest/v1/arena_invalidations?matchID=eq.${matchID}`, outsider.access_token);
  assert(hidden.ok); assert.deepEqual(hidden.data, []);
  for (const method of ['POST', 'PATCH', 'DELETE']) {
    const r = await request(`/rest/v1/arena_invalidations?matchID=eq.${matchID}`, host.access_token,
      method === 'DELETE' ? undefined : { matchID, revision: 999 }, method);
    assert(!r.ok, `${method} must not be permitted`);
  }
  for (const table of ['arena_rooms', 'arena_players', 'arena_command_receipts', 'arena_courses']) {
    assert(!(await request(`/rest/v1/${table}?select=*`, host.access_token)).ok);
    assert(!(await request(`/rest/v1/${table}?select=*`, host.access_token, undefined, 'GET',
      { 'Accept-Profile': 'private' })).ok);
  }
  assert(!(await request('/rest/v1/rpc/arena_is_member', host.access_token, { room_id: matchID })).ok);
  passed('private tables/helpers are not exposed and clients cannot forge or delete invalidations');

  const invalid = [
    [null, 'invalidCommand'], [[], 'invalidCommand'], [{ ...create, id: randomUUID(), contractVersion: 2 }, 'incompatibleContract'],
    [{ ...create, id: 'invalid' }, 'invalidCommand'],
    [command({ createRoom: { nickname: ' ', course, algorithm: 'dijkstra' } }), 'invalidCommand'],
    [command({ createRoom: { nickname: 'H'.repeat(25), course, algorithm: 'dijkstra' } }), 'invalidCommand'],
    [command({ createRoom: { nickname: 'Host', course: { ...course, version: 'unknown' }, algorithm: 'dijkstra' } }), 'incompatibleCourse'],
    [command({ createRoom: { nickname: 'Host', course, algorithm: null } }), 'invalidCommand'],
    [{ ...scoped(s, { setReady: { ready: 'true' } }) }, 'invalidCommand'],
    [{ ...scoped(s, { setReady: { ready: null } }) }, 'invalidCommand'],
    [scoped(s, { setReady: { ready: true, userID: guest.user.id } }), 'invalidCommand'],
    [scoped(s, { confirmArrival: { nodeID: '01-jms', evidence: { organiserApproval: { approvalID: 'fake' } } } }), 'invalidApproval'],
    [scoped(s, { submitAnswer: {} }), 'invalidCommand'],
    [scoped(s, { confirmAlgorithm: { algorithm: null } }), 'invalidCommand'],
  ];
  for (const [cmd, expected] of invalid) errorCode(await send(host, cmd), expected);
  assert.equal((await snapshot(host, matchID)).revision, s.revision);
  passed('malformed input, spoofed identity, unsupported courses and client-side arrival bypasses are rejected without writes');

  const retry = scoped(s, { confirmAlgorithm: { algorithm: 'aStar' } });
  const retries = await Promise.all(Array.from({ length: 5 }, () => accept(host, retry)));
  assert(retries.every(r => JSON.stringify(r) === JSON.stringify(retries[0])));
  assert.equal(retries[0].acceptedRevision, s.revision + 1);
  s = retries[0].snapshot;
  passed('simultaneous delivery of one command commits exactly once');

  const simultaneous = await Promise.all([
    send(host, scoped(s, { setReady: { ready: false } })),
    send(guest, scoped(s, { confirmAlgorithm: { algorithm: 'aStar' } }))
  ]);
  assert.equal(simultaneous.filter(r => r.ok).length, 1);
  errorCode(simultaneous.find(r => !r.ok), 'staleRevision');
  passed('concurrent distinct commands cannot overwrite a stale revision');

  for (let i = 0; i < 4; i++) {
    const fresh = (await makeRoom(host, i % 2 ? 'aStar' : 'dijkstra')).receipt.snapshot;
    const racers = await Promise.all([guest, outsider].map(session => send(session,
      command({ joinRoom: { code: fresh.room.roomCode, nickname: 'Racer' } }))));
    assert.equal(racers.filter(r => r.ok).length, 1);
    errorCode(racers.find(r => !r.ok), 'roomFull');
    const room = await snapshot(host, fresh.room.matchID);
    assert.equal(room.room.players.length, 2); assert.equal(room.revision, 2);
  }
  passed('four competing-join races each admit one guest and never overfill the room');
  const final = await snapshot(host, matchID);
  const guestView = await snapshot(guest, matchID);
  assert.deepEqual(final.room, guestView.room);
  assert.deepEqual(final.viewer.feedback, []); assert.deepEqual(final.viewer.submissions, []);
  // Optional local output supports an independent Swift decoder check; contains no tokens.
  if (process.env.ARENA_WIRE_OUTPUT) writeFileSync(process.env.ARENA_WIRE_OUTPUT,
    JSON.stringify({ receipt: created, snapshot: final, invalidation: { matchID, revision: final.revision } }, null, 2));
  passed('authorised snapshots agree, identify each viewer and contain no private challenge bank');
  console.log(`Passed ${checks} lobby integration checks.`);
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });
