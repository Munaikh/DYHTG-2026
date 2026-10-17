# Plot Twist Duel

Indoor two-player prediction mode for Dijkstra and A*. It is independent of the outdoor checkpoint tables, arrival validation, and location permissions. Deployed to the existing **DYHTG-Hackathon** project (`gftmvsmamkpvqrvbhoze`) on 17 October 2026 with additive migration `20261017194006_plot_twist_duel.sql`.

## Client contract

Authenticate with the existing anonymous Supabase session. Never send a caller-supplied player ID. Public RPCs return a `DuelSnapshot` JSON object directly:

- `arena_duel_command({"command": DuelCommand})`
- `arena_duel_snapshot({"match_id": UUID})`

The authoritative Swift definitions are in `Packages/AlgorithmArenaCore/Sources/AlgorithmArenaCore/DuelModels.swift`. Codable uses flat camelCase keys. IDs are UUIDs; node IDs are strings. `roundIndex` is zero-based and `roundCount` is three. Optional `currentRound` and `reveal` keys are omitted when unavailable. Poll the snapshot every second while a room is open; polling resumes after reconnect. This mode does not require Realtime configuration.

Commands have a fresh UUID `id`, an action string, and optional `matchID`, `revision`, `nickname`, `code`, `algorithm`, `answerNodeID`:

| Action | Fields and behavior |
|---|---|
| `create` | `nickname`, `algorithm` (`dijkstra` or `aStar`); returns a six-character room code |
| `join` | `nickname`, `code`; case-insensitive room code; maximum two authenticated identities |
| `ready` | `matchID`, latest `revision`; marks the caller ready |
| `start` | Host only; both players must be ready |
| `submit` | `answerNodeID`; caller can lock one prediction per round |
| `advance` | Marks the caller as finished reading the reveal; both must advance |
| `leave` | Ends an unfinished duel as `incomplete` for both players |
| `rematch` | Host only after `finished`; resets score/readiness and returns to lobby |

Every action after entry requires `matchID` and the latest `revision`. Phases are `lobby → answering → reveal` for each round, then `finished`. A wrong answer still advances and receives a worked explanation. Scores are 100 per correct prediction, zero otherwise; there is no speed bonus.

For an uncertain transport outcome, retry the **identical command and UUID**. Accepted commands are stored and replay their original snapshot. Never apply a response whose revision is older than the state already displayed. Reusing a command UUID with altered content returns `commandConflict`. For `staleRevision`, refresh the snapshot, reconcile the intent, and send an applicable retry with a **new** UUID. Simultaneous submissions at one revision deliberately result in one success and one stale response; the second player can retry after refreshing. Do not automatically retry a choice against a different round.

Errors use PostgREST's error body with a JSON string in `message`, containing `code`, `message`, and sometimes `currentRevision`. Expected codes include `staleRevision`, `notMember`, `roomFull`, `roomNotFound`, `notReady`, `hostOnly`, `invalidPhase`, `alreadySubmitted`, `invalidAnswer`, `invalidNickname`, and `commandConflict`.

## Authored content

Each algorithm has three independent duel scenarios, separate from the learning lesson bank:

1. **Power up:** select the next node after the source expansion.
2. **Bridge closed!:** A→C is removed. Start a fresh search and predict the next expansion after S and A. `previousScenario` supplies the old graph for a ghost comparison. The optimal route changes from cost 6 to cost 9.
3. **New world, same rule:** a different topology tests transfer; Dijkstra chooses D, A* chooses E.

The fixtures were exported from the actual Swift `SearchEngine`, including its deterministic node-ID tie rule and validated A* heuristics. `presentedState.frontier` is alphabetically ordered to avoid giving the priority answer away through array position. Its costs and settled list still match the exact decision boundary. UI must compute priority when explaining the answer instead of assuming this public frontier is ordered by priority.

Authoring source: `scripts/export_duel_content.swift`. Compile it with the Core sources (it deliberately is not an app-linked package target):

```sh
swiftc -module-cache-path /tmp/duel-swift-module-cache Packages/AlgorithmArenaCore/Sources/AlgorithmArenaCore/*.swift scripts/export_duel_content.swift -o /tmp/export-duel-content
/tmp/export-duel-content content/duel/v1/server
```

The exported `content/duel/v1/server/*.json` files are **server-only answer banks**. Do not include them in the app target. A content change requires a new migration; do not edit a deployed migration.

## Privacy and concurrency

All five new tables live in the unexposed `private` schema, have RLS enabled, and grant no direct client access. Public functions are security-invoker wrappers. Their private security-definer implementations have an empty search path, enforce `auth.uid()` and room membership, and grant execution only to `authenticated`.

The command transaction locks the caller identity and room. Two-seat constraints provide a second capacity invariant. Submission uniqueness is scoped to room, rematch generation, round, and authenticated identity. Rematch retains historical receipts/submissions in their original generation.

A public answering snapshot includes only the graph, the presented search state, choices, and submission booleans. It excludes answer keys, all submitted choices, future trace steps, and newly earned score. Both predictions and scores are released together after both players submit. Nonmembers receive the same `notMember` response for absent and inaccessible snapshot IDs.

## Verification

The local migration was tested transactionally in the running Supabase Postgres container before hosted deployment. Local and hosted end-to-end tests each passed all 15 grouped checks for both algorithms:

- Independent real anonymous Auth identities and unauthenticated rejection.
- Private schema/table access denial.
- Exactly-once create, immutable command identity, capacity, membership, readiness and host permissions.
- Racing submissions, stale revision recovery, duplicate submissions, invalid choices, and exact scoring.
- No answer/trace/choice/score disclosure until the shared reveal.
- Auth token refresh and state recovery while reading the reveal.
- All three rounds including wrong answers, mutual advance, matching final results, clean rematch, and explicit leave.

```sh
node scripts/test_supabase_duel.mjs
DUEL_WIRE_PATH=/tmp/duel-hosted-wire.json node scripts/test_supabase_duel.mjs --remote
DUEL_WIRE_PATH=/tmp/duel-hosted-wire.json swift test --package-path Packages/AlgorithmArenaCore --filter DuelContractTests
```

Hosted tests create anonymous test identities and test rooms; no organiser or service-role credentials are required. The wire corpus contains snapshots/errors only, with no access or refresh tokens. It is written to `/tmp/duel-wire.json` by default.

The three Swift tests passed against the hosted corpus, verifying Codable interoperability, all six canonical traces, valid choice keys, twist route changes, and the final scenario's algorithm-dependent answer. Local security advisors returned no warnings. Hosted advisors added only informational RLS-with-no-policy notices for the intentionally inaccessible private tables; the pre-existing outdoor anonymous-invalidation and disabled leaked-password warnings remain unchanged.

These backend checks do not establish visual, simulator, or physical-device acceptance of the SwiftUI client. The parent implementation validates those separately.

For a separate player alongside one simulator, use `node scripts/duel_partner.mjs ROOMCODE --auto`. It joins with its own anonymous identity, readies itself, computes predictions from public costs, and waits for the human/simulator to continue each reveal. Omit `--auto` for interactive `ready`, `answer NODE`, `next`, `state`, and `quit` commands. It does not read private fixtures or store session tokens. Two real simulators remain the primary UI acceptance path.

## Five-algorithm question rotation (v2)

The new additive migration **20261017220000_duel_variety.sql** expands Plot Twist
Duel to the five algorithms already taught in Learn: **BFS, DFS, Dijkstra, A*,
and Greedy best-first**. This migration is prepared locally; deployment and hosted
acceptance are still required. Apply it after the existing migrations, then build
and update both players' apps. The existing room code, readiness, three-round
structure, 100-point scoring, shared reveal and recovery flow remain intact.

The public duel `algorithm` and reveal trace now use `StudyAlgorithm`, which is
shared from Core with Progression. The outdoor `AlgorithmKind` remains exactly
two cases. The same `StudySearch` implementation powers lessons and the new duel
answer bank. Legacy Dijkstra/A* wire values and saved snapshots still decode.
New `DuelTrace` uses the original trace JSON shape, extended to five algorithm IDs.

There are **120 server-only questions: 24 per algorithm**, with eight variants in
each of three round categories:

1. Predict the next expansion at different decision boundaries.
2. After a genuine connection closure, identify a predecessor in the new search.
3. Reconstruct the first hop or final connection of the algorithm's resulting route.

Graphs vary across four topology families, 7–9 nodes, algorithm-specific seeds,
node labels, edge costs and decision boundaries. Stories and wording also vary.
BFS/DFS questions use unit edges. A* estimates are half the exact remaining cost,
validated as consistent/admissible for each graph including the changed network.
DFS and Greedy route questions explicitly ask for the route the search finds;
they do not claim it is shortest. Neighbour ordering and tie rules are displayed.
The graph stays interactive for all question types; chips, tables, before/after
comparison and algorithm-specific replay descriptions use the existing UI.

Optional round keys `questionID`, `questionKind` and `focusNodeID` distinguish
questions. V1 rounds omit them and default to next-expansion behavior. The public
snapshot still contains no answer key, explanation, future trace or opponent
prediction until both players submit. Final scores and learning rewards use the
same validation and exactly-once path as before.

### Reducing repetition

At start, the server locks the room and assigns one question per category to a
private `(room,generation)` deck. Both players receive the same fixed deck. It
prefers questions unseen by **both** players, then content seen by only one, and
then the least recently seen by either. History is keyed by authenticated user,
so it also applies when creating a different room with the same account.
Questions enter history only when their round is shown, not when future rounds
are privately selected. Rematches get fresh decks. With the same pair, each
category's eight questions is exhausted before repeating; subsequent selection
uses oldest-seen content. Repetition is reduced rather than claimed impossible
with a finite bank. A fresh anonymous identity has no prior history.

Active pre-migration rooms without a v2 deck keep their original v1 questions,
answers and receipts. Their next rematch uses v2. Never edit the v1 fixtures or
rewrite a migration already deployed to a shared environment.

### Authoring and verification

```sh
swiftc -module-cache-path /tmp/duel-variety-cache \
  Packages/AlgorithmArenaCore/Sources/AlgorithmArenaCore/*.swift \
  scripts/export_duel_variety.swift -o /tmp/export-duel-variety
/tmp/export-duel-variety content/duel/v2/server
# Only while this new migration is UNDEPLOYED:
python3 scripts/build_duel_variety_migration.py

swift test --package-path Packages/AlgorithmArenaCore
bash scripts/test_duel_store.sh
node scripts/verify_duel_variety.mjs
npm install --prefix /tmp/arena-db --no-save @electric-sql/pglite@0.3.14
PGLITE_MODULE=/tmp/arena-db/node_modules/@electric-sql/pglite/dist/index.js \
  node scripts/test_duel_variety.mjs
# After migration in a local Supabase stack:
node scripts/test_supabase_duel.mjs
```

The independent JS solver checks all 120 solutions and route costs using only
public graph/state data. The PostgreSQL test loads the entire migration chain,
runs ten complete duels per algorithm (50 total), and checks identical questions,
no disclosure before reveal, stale/duplicate submissions, scoring, rematch bank
exhaustion, new-room history, inaccessible answer/history/deck tables, and v1
compatibility. It uses temporary database users and makes no hosted changes.
The production-store harness separately checks reconnection and pending-command
recovery. Hosted Auth/PostgREST/concurrency tests still need the new migration.
