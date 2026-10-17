# Supabase lobby and player sessions (#6)

This backend implements contract v1 without changing the Foundation package or
adding dependencies to the iOS target. The native `MatchService` adapter and Xcode
configuration belong to owaini0. Match rules, arrival validation, actual start,
departure, private answers and scoring belong to #7.

## Project and configuration

The dedicated project is **DYHTG-Hackathon** (`gftmvsmamkpvqrvbhoze`), under
**DYHTG** (`qzxdszpupxjbjzuntsya`), in **Frankfurt / eu-central-1**, using Postgres 17.
The owner created this project and approved Frankfurt on 17 October 2026,
replacing issue #6's original London requirement. Client-safe connection metadata
is in `supabase/client-config.json`; only a publishable key belongs in the app.

Use Supabase CLI **2.117.0**, matching CI. The committed `supabase/config.toml`
enables anonymous sign-in, refresh-token rotation, public-only API exposure and
explicit grants. Email/SMS signup, storage and other unused services are disabled.
Ports 56320–56322 keep this stack separate from other local Supabase projects.

```sh
supabase start -x storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
supabase test db
node scripts/test_supabase_lobby.mjs
supabase db advisors --local --type security --level warn --fail-on warn
```

Node 22 or later is required; the tests use built-in fetch and WebSocket, with no
npm packages. They create three anonymous users and several rooms in the selected
local stack. Repeated runs count toward the anonymous signup limit (30/IP/hour).
Reset only this isolated local database when a clean run is needed; never reset a
hosted database to run these tests. The SQL tests roll back their own fixtures.

To reproduce deployment to the dedicated project:

```sh
supabase login
supabase config diff --project-ref gftmvsmamkpvqrvbhoze
# Review the diff: this configuration is for a NEW dedicated project.
supabase config push --project-ref gftmvsmamkpvqrvbhoze
supabase db push --project-ref gftmvsmamkpvqrvbhoze
supabase migration list --project-ref gftmvsmamkpvqrvbhoze
supabase db advisors --project-ref gftmvsmamkpvqrvbhoze --type security --level warn
```

Inspect the dashboard to verify anonymous
sign-in and the `public` Data API schema after applying configuration. Keep
`private` out of exposed schemas. Never copy privileged credentials into app
resources, fixtures, logs or source control.

Use the project's URL and **publishable** API key in `supabase/client-config.json`
for the iOS adapter. `supabase/.env.example` documents local overrides. Privileged
credentials and player session tokens are never committed. Pin the exact Supabase Swift package version and
commit `Package.resolved` when the client owner introduces that dependency; the
core package remains independent of Supabase. This change adds no SDK dependency.

A hosted smoke test can use the same harness with `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`, and explicit `--remote`. It creates real test users and
rooms, so run it only against this dedicated development project. It never needs
a service-role key and never prints Auth tokens.

## Authentication and restoring a player

On first use, call Supabase anonymous sign-in and persist the returned session
using the native SDK's secure session storage (Keychain on iOS). An anonymous
**Auth user** has the Postgres `authenticated` role; the unauthenticated API
`anon` role has no room access. Identity comes exclusively from the validated JWT
`sub` / `auth.uid()`. Nicknames and user-editable JWT metadata grant no authority.

On relaunch, restore/refresh the existing session before reading the room. Do not
sign in anonymously on every launch: a fresh identity cannot recover another
identity's membership. A nickname or room code cannot restore a lost session.
Keep the access/refresh tokens outside `ReconnectState` JSON and do not log them.
There is no account linking or persistent account recovery in this MVP.

Persist the entire pending `MatchCommand` before sending, including its UUID,
original scope/revision and payload. Persist the active match and last confirmed
snapshot separately with the restored session identity. After refresh/reconnect:
fetch, subscribe, fetch again to cover the subscription race, then retry the exact
uncertain command. Ignore older returned receipts and refetch when necessary.
The REST integration test verifies refresh-token identity continuity; secure
on-device persistence remains part of the native adapter's acceptance.

## Transport mapping (existing contract v1)

| Operation | PostgREST request | Response |
| --- | --- | --- |
| Send | `POST /rest/v1/rpc/arena_command`, body `{"command": <MatchCommand>}` | `CommandReceipt` |
| Read | `POST /rest/v1/rpc/arena_snapshot`, body `{"match_id": "<match ID>"}` | `MatchSnapshot` |
| Subscribe | Postgres Changes on `public.arena_invalidations`, filter `matchID=eq.<match ID>` | Row `{ "matchID": "...", "revision": 2 }` |

Send `apikey: <publishable key>` and `Authorization: Bearer <player access token>`.
Use `ContractJSON` at the Swift boundary. UUID-backed identifiers encode as strings;
server timestamps are whole-second UTC ISO-8601. Optional nil fields are omitted,
matching Swift's synthesized Codable representation. Action/scope enum objects
match the examples under `contracts/v1/commands/` exactly.

PostgREST business failures use SQLSTATE `P0001`. Decode its `message` JSON as
`MatchServiceError`; its `code` is the stable application error, distinct from the
outer PostgREST `code`. A member's `staleRevision` includes `currentRevision`.
Non-members receive `notMember` for both unknown IDs and someone else's room, with
no revision or snapshot. Missing JWTs may be rejected by the API before RPC; map
transport 401/permission failures to authentication recovery, not command retries.

## Lobby behavior

- `createRoom`: validated nickname (trimmed, 1–24 characters, no control characters),
  registered course version and either algorithm. The creator occupies seat one.
- `joinRoom`: accepts a ten-character hexadecimal room code, ignoring surrounding
  spaces and letter case. Exactly one guest occupies seat two. An existing member
  joining again with the same nickname receives the current snapshot with no new
  membership/revision. Invalid codes return `roomNotFound`; full rooms `roomFull`.
- `selectAlgorithm`: creator and lobby only. An actual algorithm change clears
  **both** confirmations and ready states atomically.
- `confirmAlgorithm`: member and lobby only; must match the current selection.
- `setReady`: member and lobby only; `true` requires that player's confirmation.
- `start`: creator only; requires two confirmed/ready players and server-verified
  shared-start arrivals. No client can write the arrival field. Until #7 wires
  verified arrivals and the transition, it cannot start a match and returns
  `arrivalRequired` (or `serviceUnavailable` if trusted test data has both arrivals).
- Other game commands fail explicitly until #7 implements their authority checks.

Each match command checks membership, exact course and expected revision under the
room lock. Every accepted state-changing lobby command increments the revision.
The same command UUID and JSON payload for the same authenticated user returns
its **original** receipt before stale-revision validation, including create/join
and ready retries. JSON member ordering is immaterial. A changed payload with the
same ID fails `idempotencyConflict`. Store receipts for the full room recovery
lifetime; do not prune them while clients can still retry.

Concurrent requests from one session serialize before receipt lookup. All room
changes serialize under a row lock. A unique `(room_id, seat)` with a two-seat
check and unique membership provide a second capacity invariant. Receipts, state,
revision and invalidation update commit together; failed commands leave none of
these changes behind. Snapshot reads take a share lock on that same room to avoid
mixing player states from different revisions.

The lobby snapshot has no challenges, submissions, rewards or verified arrivals
until the server validates them. `connection: online` is a lobby projection
placeholder, not an authoritative network-presence signal. The adapter tracks
its own disconnected/reconnecting state; loss of connectivity never calls `leave`.
#7 must extend the snapshot projection with real match state and gated feedback.

## Database boundary and #7 handoff

`private.arena_courses`, `arena_rooms`, `arena_players` and
`arena_command_receipts` have RLS and no client table privileges. Only the
invalidation table is exposed, with member-only SELECT and no client writes.
There is no API for enumerating rooms by code or reading private tables directly.

The public RPC wrappers use `SECURITY INVOKER`. Their private `SECURITY DEFINER`
implementations deliberately perform trusted mutations on behalf of `auth.uid()`;
each checks caller identity and membership/ownership. All use an empty search
path with qualified references. Internal helpers revoke default PUBLIC execution.
The authenticated role gets only the explicitly named private entry points it
needs to invoke the public wrappers and evaluate RLS; `private` is not exposed by
PostgREST. Do not add generic privileged SQL, arbitrary filters, user IDs, score
parameters or raw table write grants to extend this API.

Only `arena_invalidations` is added to `supabase_realtime`. Clients refetch an
authorised snapshot; no full room, receipt, answer, raw GPS, feedback or reward is
replicated. Keep #7 submissions, answer keys, organiser proofs and unreleased
feedback in non-exposed, non-published storage. Reuse the existing transaction,
revision and receipt boundary when adding match transitions and the reward ledger.

The only registered course is the versioned Gilmorehill survey candidate. It is
marked `surveyed=false`; lobby creation is allowed, but this migration supplies
no trusted GPS validation or outdoor readiness claim. #7 must enforce course
readiness, exact start-node verification and all match prerequisites server-side.

The hosted security scan reports the expected anonymous-access policy: anonymous
Auth users are the product's players, and `arena_member_invalidations` additionally
checks their actual room membership. See the [anonymous policy advisory](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins).
Private-table RLS-without-policy notices describe deliberate default denial;
clients have no table grants. The password-protection notice concerns a password
flow unused by this anonymous-only app with email/SMS signup disabled; see
[password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
The follow-up migration removes client execution grants from the default hosted
`rls_auto_enable` helper where present, without changing its event-trigger role.

## Verified deployment (17 October 2026)

- Both migrations are applied in `gftmvsmamkpvqrvbhoze`; their checked-in versions
  match the hosted migration history.
- A clean local rebuild passes 26 pgTAP security/capacity assertions.
- All 13 REST/Auth/Realtime integration checks pass locally and on the hosted
  project, including four competing-join races and simultaneous command retries.
- Actual SQL receipts, snapshots and invalidations decode with the unchanged
  Swift contract v1 models. The existing Swift core/learning suite passes.
- Hosted publication membership contains only `public.arena_invalidations`.
  Temporary hosted test users and rooms were removed after the smoke test.

Actual iOS Keychain persistence, native adapter integration and physical two-phone
acceptance remain separate from these backend results.

## References checked for this implementation

- [Anonymous Auth sessions](https://supabase.com/docs/guides/auth/auth-anonymous)
- [Database functions and privileges](https://supabase.com/docs/guides/database/functions)
- [Postgres Changes and RLS](https://supabase.com/docs/guides/realtime/postgres-changes)
- [Explicit Data API grants](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically)
