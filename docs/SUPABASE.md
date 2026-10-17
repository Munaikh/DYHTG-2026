# Supabase rooms, match rules, scoring and reliability (#6–#8)

This backend implements contract v1 without changing the Foundation package or
adding dependencies to the iOS target. The native `MatchService` adapter and Xcode
configuration belong to owaini0. The backend now implements match rules, verified
arrivals, departure, private answers and scoring.

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
node scripts/test_supabase_match.mjs
supabase db advisors --local --type security --level warn --fail-on warn
```

Node 22 or later is required; the tests use built-in fetch and WebSocket, with no
npm packages. They create three anonymous users per script and several rooms in the selected
local stack. Repeated runs count toward the anonymous signup limit (30/IP/hour).
Reset only this isolated local database when a clean run is needed; never reset a
hosted database to run these tests. The SQL tests roll back their own fixtures.

To reproduce deployment to the dedicated project:

```sh
supabase login
supabase config diff --project-ref gftmvsmamkpvqrvbhoze
# Review the diff: this configuration is for a NEW dedicated project.
supabase config push --project-ref gftmvsmamkpvqrvbhoze
supabase db push --linked --project-ref gftmvsmamkpvqrvbhoze
supabase migration list --linked --project-ref gftmvsmamkpvqrvbhoze
supabase db advisors --linked --project-ref gftmvsmamkpvqrvbhoze --type security --level warn
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
  shared-start arrivals. No client can write the arrival field. Starts both players
  in the unscored opening prediction. Missing arrivals return `arrivalRequired`.

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
Match snapshots project each player's actual stage, released score, pending reward
maximum and remaining points, plus viewer-only questions, submissions and feedback.

## Database boundary

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
replicated. Submissions, answer keys, organiser proofs and rewards stay in the
private schema. Match transitions reuse the lobby transaction, revision and
receipt boundary. Submissions and the reward ledger reject UPDATE/DELETE.

The only registered course is the versioned Gilmorehill survey candidate. It is
marked `surveyed=false`; lobby creation and organiser-approved demos are allowed.
GPS arrivals require a surveyed course. The server checks the frozen coordinates,
25 m radius, maximum 10-second fix age (future fixes fail), and accuracy from
0 through 20 m. Invalid fixes return the contract error; the unsurveyed candidate
returns `serviceUnavailable` for an otherwise valid GPS arrival.

The hosted security scan reports the expected anonymous-access policy: anonymous
Auth users are the product's players, and `arena_member_invalidations` additionally
checks their actual room membership. See the [anonymous policy advisory](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0012_auth_allow_anonymous_sign_ins).
Private-table RLS-without-policy notices describe deliberate default denial;
clients have no table grants. The password-protection notice concerns a password
flow unused by this anonymous-only app with email/SMS signup disabled; see
[password security](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
The follow-up migration removes client execution grants from the default hosted
`rls_auto_enable` helper where present, without changing its event-trigger role.

## Lobby foundation verification (17 October 2026)

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

## Authoritative match commands (#7)

Migration `20261017173114_authoritative_match_rules` is deployed to the dedicated
`DYHTG-Hackathon` project. The hosted database has all 12 private challenge
documents, no client grants on private tables, and only match-ID/revision
invalidations in Realtime. The hosted security scan reports only the expected
anonymous-player membership policy and intentional private-table default denial.

Use the existing `arena_command` and contract-v1 `MatchAction` payloads. Every
mutation checks identity, membership, course version, expected revision, phase
and the viewer's progression, under the room lock.

- `confirmArrival`: verifies the start in the lobby or the current walking target.
  Arrival opens only the chosen checkpoint's question.
- `start`: creator only; two ready, confirmed players with verified start arrivals.
- `submitAnswer`: one immutable first answer per question. Uses the exact
  Swift-exported server documents in `content/learning/v1/server`; clients send
  an answer, never correctness or points. Wrong answers award zero and progress.
- `chooseRoute`: after checkpoint one, locks standard or bonus. The middle
  question appears only after locking AND arrival. Each route has three stops.
- `finish`: verifies the finish after all three chosen checkpoint submissions;
  adds 20 once. `confirmArrival` at the finish uses the same rules.
- `leave`: records an incomplete result. Disconnect/background does not send it.

Shared first/third questions release correctness, points, explanation, replay
and both answers together only after both submissions. Until then, snapshots
show pending feedback and the question's maximum possible reward, including for
a wrong answer. A first submitter may immediately continue walking. Other
feedback is immediate and self-only.

The ledger yields maxima of 80 standard / 100 bonus. Practice and the final
understanding check award zero. A finished player gets the understanding check
immediately while waiting; its first node/reason answers are recorded separately.
The room returns winner/draw only after both finish. Public state is identical
for both viewers; pending shared awards remain hidden even on departure.
Navigation contains only the next leg's authored edges, including the branch rejoin.

### Organiser-approved demo arrivals

An administrator provisions an organiser by setting trusted Auth `app_metadata`
`arenaOrganiser: true`. This capability is read from `auth.users`, so revoking it
takes effect immediately. User metadata and room creation grant no such access.
The organiser calls:

```json
POST /rest/v1/rpc/arena_issue_arrival_approval
{ "match_id": "<match ID>", "player_id": "<player ID>", "node_id": "<current target>" }
```

The response is `{ "approvalID": "<opaque UUID>", "expiresAt": "<UTC time>" }`.
Pass that ID through `ArrivalEvidence.organiserApproval` in the player's command.
Proofs expire in two minutes, bind the player/room/node, and are single use.
Issuance allows 30/minute per organiser; accepted verifications allow 5/minute
per player/match. Invalid tokens reveal no proof details. Both issuing and using
a proof are recorded privately; the snapshot records `method: organiserApproval`.
The app never receives an organiser password or privileged API key.

The match test completes Dijkstra at 80/100 and an A* draw at 40/40,
checks pending/released feedback, locked routes, duplicate deliveries, unscored
understanding checks, restoration and departure. It provisions an organiser only
on localhost using the local admin key in memory. Hosted development runs require
`--remote`, client-safe environment configuration, and `ARENA_ORGANISER_TOKEN`.
The test creates users/rooms; do not point it at a production project.

## Reliability checks and iOS handoff (#8)

Run from the repository root with Docker, Supabase CLI **2.117.0**, Node **22+**
and Swift **6+**. CI pins Node **22.22.0**. No npm dependencies are needed.

```sh
supabase test db
node scripts/test_supabase_lobby.mjs
ARENA_MATCH_WIRE_OUTPUT=/tmp/arena-match-wire.json node scripts/test_supabase_match.mjs
ARENA_MATCH_WIRE_OUTPUT=/tmp/arena-match-wire.json swift test --package-path Packages/AlgorithmArenaCore
python3 scripts/verify_search_fixtures.py
python3 -B scripts/verify_learning_content.py
supabase db advisors --local --type security --level warn --fail-on warn
supabase db query --local --file supabase/verify_deployment.sql
```

The match harness compares the running local database's course and all 12 private
documents with the checked-in Swift exports. Every unlocked prompt and released
explanation/replay is checked against that bank. It can write a token-free corpus
of actual receipts, snapshots and application errors; the Swift test decodes it
with the production contract types. Without `ARENA_MATCH_WIRE_OUTPUT`, ordinary
Swift tests skip only that live-response check. The Supabase workflow requires
the corpus and runs its decoder on macOS after the backend job succeeds.

| Coverage | Automated evidence |
| --- | --- |
| Room capacity and stale writes | Four competing-join races; only one command at a shared revision commits |
| Start, route, answer, finish | Concurrent distinct UUIDs; original receipt retries; reconcile the losing player's action |
| Scoring and feedback | Dijkstra standard/bonus 80/100; A* wrong first/middle answers yield 40/40; pending feedback hides correctness and rewards; middle feedback is self-only |
| Permissions | Third identity rejected by match commands/snapshot/override RPCs; member-only invalidations; all private tables denied to clients |
| Recovery | Refresh preserves player identity; dropped Realtime connection recovers missed changes with fetch/subscribe/fetch; old pending receipt cannot replace a newer released snapshot |
| Departure | Explicit leave yields incomplete, including when a shared answer/reward remains unreleased |
| Overrides | Role spoofing/revocation, wrong player/room/node, expiry, single use, private issue/use logs, 30/minute issuance and 5/minute redemption limits |
| Contract/version | Live server responses decode in Swift; unsupported course versions fail without mutation; content and course equal the authored exports |

For the iOS adapter, reconcile these cases using the same saved Auth identity:

1. **Request never reached the server:** refetch and resend the saved command
   unchanged. If another action advanced the room, handle `staleRevision` using
   the new snapshot; do not assume the action was accepted.
2. **Request committed but its response was lost:** resend the original UUID,
   revision and payload. Apply its receipt only if it supersedes local state,
   then refetch. An older receipt may still show pending feedback.
3. **Background/relaunch or missed invalidations:** restore/refresh the session,
   fetch, subscribe, fetch again. Ignore invalidations/receipts at older revisions
   and resume from the newest authorised snapshot. Connectivity loss never sends
   `leave`; do not create another anonymous identity.

Secure Keychain persistence, native network interruption handling and outdoor
two-phone GPS/AR acceptance remain with #14/#15. These backend tests do not
establish those device behaviours.

### Provision and revoke a demo organiser

An operator signs in with their own Auth session. In the dedicated project's SQL
Editor, an administrator grants that specific Auth user the capability:

```sql
update auth.users
set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||'{"arenaOrganiser":true}'::jsonb
where id='<organiser Auth user UUID>'::uuid;
```

Keep admin/service-role credentials on the server/operator machine. Keep the
organiser's session with the operator; players receive only the short-lived
`approvalID` from the RPC documented above. Never bundle an organiser token in
the app or give players a shared organiser login. The local harness grants its
test host this capability using the **local** admin key only, held in memory.

To revoke issuance immediately, remove the trusted flag:

```sql
update auth.users set raw_app_meta_data=raw_app_meta_data-'arenaOrganiser'
where id='<organiser Auth user UUID>'::uuid;
```

Existing issued proofs remain usable until consumed or their two-minute expiry.
For an audit, inspect `private.arena_arrival_approvals` by room/player/issuer;
`created_at`, `expires_at` and `used_at` record issuance and successful use.
`private.arena_arrivals.method` and the authorised snapshot identify overrides.
Keep proof IDs and sessions out of shared logs. On `rateLimited`, wait the
returned `retryAfterSeconds`; on `invalidApproval`, obtain a new bound proof.

### Deployment verification and demo reset

Use the configuration/migration commands near the top of this runbook. This issue
adds tests and documentation, with no schema migration. After deployment, run:

```sh
supabase db query --linked --project-ref gftmvsmamkpvqrvbhoze --file supabase/verify_deployment.sql
```

If the CLI cannot initialise its database connection, run the contents of
`supabase/verify_deployment.sql` in the dedicated project's SQL Editor instead.
The same read-only query was verified locally via CLI and on the hosted project
via the Supabase connector on **17 October 2026**: matching migration/course/content
versions, zero private client grants, and only the invalidation table published.

Expected migrations: `20261017171103`, `20261017171212`, `20261017173114`.
Expected course: `gilmorehill-jms-library` / `candidate-2026-10-17-1`, unsurveyed.
Expected content: `2026-10-17.1`, six slots each for `dijkstra` and `aStar`.
Only `public.arena_invalidations` belongs in Realtime and `private_client_grants`
is zero. Verify anonymous Auth enabled and API exposure limited to
`public` in the dashboard. Client configuration is `supabase/client-config.json`.
If versions drift, stop integration and apply/review the missing migration;
do not edit the existing course/content version in place.

For a **hosted demo replay**, explicitly leave the old room, reconcile its pending
commands, then create a new room/code with the same player sessions. The new room
starts with empty submissions and rewards. Keep old rooms/receipts for recovery
and audit; no reset/delete RPC is exposed. Immutable answer/reward records are
deliberate. Do not delete Auth users to reset a match.

For a **clean local rebuild only**, the following resets the `algorithm-arena`
stack configured in this checkout, deleting its local test rooms/users and
reapplying all migrations:

```sh
supabase db reset --local --no-seed
```

Use no `--linked`, `--project-ref` or hosted database URL for a reset. Re-run the
checks above afterwards. Six anonymous signups per full test run count against
the 30/IP/hour limit; database reset does not promise to clear the running Auth
service's rate counter. If sign-in is rate limited, wait for its window before
rerunning. Avoid changing the hosted limit just to make tests pass.

Database tests use rolled-back fixtures, following the official
[Supabase testing guide](https://supabase.com/docs/guides/local-development/testing/overview).

Local evidence on **17 October 2026**: **56 pgTAP assertions**, **13 lobby checks**,
both full match scenarios and pending-feedback departure, **43 Swift tests**
(including real-response decoding), **22 search traces** and **12 authored
challenges** pass. Local security advisors report no warnings. The hosted advisor
still reports the expected anonymous-member policy described above; private-table
default-denial notices are informational. The complete reliability suite ran
locally; the hosted verification in this issue was read-only.
