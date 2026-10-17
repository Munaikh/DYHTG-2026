# Shared contracts v1

Implementation handoff for [issue #3](https://github.com/Munaikh/DYHTG-2026/issues/3).
The Swift API lives in [`Packages/AlgorithmArenaCore`](../Packages/AlgorithmArenaCore).
The checked-in JSON under [`v1`](v1) is generated from the separate
`AlgorithmArenaFixtures` development product. Neither product uses MapKit, ARKit,
SwiftUI, Supabase, or third-party dependencies.

**Status: implemented for review. Both developers must review this boundary before
dependent integrations lock it.** The search engine and dynamic campus graph
builder are now implemented for #4; see [the routing API](../docs/SEARCH.md).
Xcode integration and server authority remain separate work.

## Wire format and compatibility

Use `ContractJSON.encoder()` / `.decoder()` in Swift. Field names and enum values
are case-sensitive. Associated-value enums use a single case key with a named
payload; empty cases use an empty object. For example:

```json
{"action":{"submitAnswer":{"challengeID":"fixture-dijkstra-first-v1","answer":{"node":{"nodeID":"B"}}}}}
```

This is an action excerpt; the complete command also requires `contractVersion`,
`id`, and `scope`. See [a full submission](v1/dijkstra/submit-command.json) and
[its receipt](v1/dijkstra/submit-receipt.json). Do not rename Swift enum cases or
associated-value labels without considering the wire impact. Do not rely on
object-key ordering. Dates are UTC ISO-8601 strings at whole-second precision.
Optional values are omitted when nil; decoders also accept explicit null.
An omitted `g` means infinity/undiscovered, never zero. All costs are non-negative
integers; numeric JSON values must be finite. Revisions fit the JavaScript safe
integer range, start at 1, and increase monotonically for the match.

`contractVersion: 1` identifies this wire contract. Unknown versions and unknown
enum cases fail decoding; adapters map these failures to `incompatibleContract`
and an update/recovery UI. Additional object fields may be ignored, so additive
optional fields are compatible; required-field removals, meaning changes, and
enum changes need a new version and fixtures.
Commands, snapshots, and course documents carry the version explicitly; nested
values and standalone trace/challenge examples inherit the negotiated `/v1` contract.

IDs are opaque, nonempty, stable ASCII strings, independent of labels, ordering,
nicknames, and coordinates. Compare IDs exactly. The typed Swift identifiers
encode as strings. A `CourseReference` pairs an ID with an immutable version;
course geometry, cost, stops, arrival thresholds, or access changes require a new
version. A challenge ID plus `contentVersion` identifies immutable authored
content. A scenario ID fixes its graph, source, goal, and question state. Production
IDs must never reuse the `fixture-` or `synthetic-` namespaces.

The data structs are transport values, not security validators. Live adapters and
the server validate membership, identifier and numeric constraints, graph
references, phase prerequisites, and cross-field invariants. Decoding successfully
does not authorise a command or certify that a course is safe.

## Course and trace

[`course.json`](v1/course.json) includes start, finish, checkpoint one, both middle
alternatives, checkpoint three, complete standard/bonus edge sequences, directed
polyline order, costs, difficulty, and reward maxima. A bidirectional edge's
polyline reverses for reverse travel. Each branch visits exactly three checkpoints
and rejoins at checkpoint three. Challenge graph scenarios are separate from the
walking graph and do not derive their source, goal, or state from a player's branch.

**This course is synthetic and is not for outdoor navigation.** Its coordinates
are near (0, 0), its 500/575 m costs are illustrative, and the polylines are not
surveyed measurements. It remains unchanged for existing mock consumers. The
additive [`courses/gilmorehill-jms-library`](v1/courses/gilmorehill-jms-library)
directory contains a versioned `awaitingSurvey` candidate, pedestrian network,
per-goal heuristics, dynamic selection graphs, routes and traces. Its coordinates
and polylines are desktop estimates; the [survey record](../docs/COURSE_SURVEY.md)
lists the outstanding checks. Do not promote a candidate to `surveyed` merely to
enable the app. Live adapters must call `requireOutdoorReadiness()`.

Arrival uses an explicit action. Suggested fixture thresholds are radius 25 m,
maximum age 10 seconds, and maximum horizontal accuracy 20 m. They are course
configuration, not app constants. The authoritative validator must accept values
at the threshold and reject larger values, future-dated fixes, invalid coordinates,
negative/unknown accuracy, and negative/nonfinite ages or distances. Freshness
uses server time. Boundary validation and field testing belong to #4/#7/#8.
`organiserApproval` carries an opaque, expiring, single-use server-issued proof
bound to player, match, and stop; no client flag or embedded organiser credential
can bypass arrival. Confirmed arrivals record the method used.

`SearchTrace` is shared by 2D and AR. Every step has an event and the complete state
immediately after it. Index zero is the initial state. Costs include g, h, and the
predecessor; compute f as g+h. Frontier order is ascending g for Dijkstra or g+h
for A*, then ascending ASCII node ID. Neighbours use the same ID ordering and
equal-cost alternatives preserve the predecessor. `relax` records the previous
cost, candidate cost, and whether the candidate was accepted. The final route is
separate from the explored nodes. `unreachable` represents no final route.

The original hand-authored traces exercise a cheaper replacement and an explored
branch absent from the final route. Engine tests check those examples independently.
New [`search`](v1/search) fixtures cover relaxation, ties, zero-cost cycles,
parallel edges, unreachable goals, differing optimal routes and identical endpoints.
Engine cost arrays are node-ID ordered; settled arrays retain expansion order.
`relax` includes rejected equal-cost and already-settled neighbour attempts.
Costs, heuristics and computed priorities must fit `0...9007199254740991` for exact
server integers; invalid graphs, invalid A* heuristics and arithmetic overflow throw.
The original practice and transfer questions remain synthetic development
content. The [authored #5 learning bank](../docs/LEARNING.md) now provides all
question slots, answer fixtures, worked explanations and full engine replays in
the separate server-only `AlgorithmArenaLearning` product.
Each question slot has a distinct graph so an earlier released replay cannot
disclose a later scored question. Both players still get the same shared-checkpoint
scenario, irrespective of branch.

The learning bank adds optional `ScenarioNode.position` (normalised illustrative
diagram x/y, never GPS or edge costs) and `ReleasedFeedback.workedStepTraceIndices`
(one replay-index array per worked step). Existing documents omit both fields;
old decoders may ignore them. New decoders accept their absence. See the learning
handoff for layout and replay fallbacks. Answer banks remain outside core and the
production app, with no change to the pending-feedback wire shape.

`CampusPathNetwork` contains paths and explicit junction connectivity, independent
of game stops. Each selection generates an immutable `CampusRoutingGraph` with
the snapped points, split edges, per-goal integer heuristics, and `GraphScenario`.
Its scenario ID includes the network version and selected path/coordinate bits;
changing selections changes the graph identity. Only declared junctions connect
paths; visual crossings alone do not. Snapping distances are explicit, and the
default maximum is 25 m. Routes start/end at snapped walking points without
inventing connectors across buildings or gardens. See `courses/.../requests/`
for two generated examples; these exports contain no scored challenge keys.

`python3 scripts/verify_search_fixtures.py` independently reproduces all 22 new
golden traces, validates every per-goal heuristic against exact shortest distances,
and checks measured costs and dynamic route geometry. It runs in CI alongside
the Swift tests. Both languages consume the published integer h values.

## Privacy and feedback

| Surface | Permitted data | Excluded data |
| --- | --- | --- |
| `PublicMatchState` | Room metadata, shared algorithm, progress, locked route, released scores, result | Answers, raw GPS, explanations, replay, unreleased rewards |
| `PrivatePlayerState` | This player's accepted submissions, currently unlocked questions, navigation, eligible feedback and first learning attempt | Opponent submissions before the shared gate; unreleased answer keys |
| `FeedbackAvailability.pending` | Challenge ID only | Correctness, awarded points, answer key, explanation, trace |
| `ReleasedFeedback` | Worked arithmetic, full trace, answer key, authorised submitted answers and rewards | Other private server content |
| `SnapshotInvalidation` | Match ID and revision | Snapshot, answers, rewards, raw location |

`ChallengeDefinition` is the client-safe prompt and presented search state. It has
no correct answer, explanation, or future trace steps. Authoritative answer keys
and unreleased feedback remain in server-private storage; do not serve the fixture
product or the entire authored challenge bank in a live build.

At shared checkpoints one/three, acceptance records the submitting player's answer
privately and advances progress even for a wrong answer. Until both submit, the
public score is unchanged, `pendingRewardMaximum` reports the question's possible
reward regardless of correctness, and feedback remains pending. On release, each
player can see both shared answers and feedback, and the score changes atomically.
Middle/practice/learning feedback releases immediately to that player only.

`remainingAvailablePoints` is the maximum from unattempted work plus the finish;
it excludes pending rewards and uses the bonus ceiling until a branch is chosen.
It must never vary with an unreleased answer's correctness. Standings and award
breakdowns contain released rewards only. Incomplete standings can therefore be
partial. Never infer pending correctness from the score, result, remaining points,
command response, error message, or Realtime event.

Middle prompts are available only after branch lock and arrival. The two
`sharedThird*` fixtures deliberately have identical definitions and presented
state despite different earlier branches. Learning-check records are private,
unscored first attempts; they do not block either player's finish or final result.

## Commands, revisions, and reconnect

`MatchService` exposes `send`, `snapshot(for:)`, and `invalidations(for:)`. A service
instance is bound to the authenticated anonymous session; player identity is never
accepted from a command. Persist credentials securely in the platform adapter,
not in these JSON files. Do not log private snapshot bodies or approval proofs.

`MatchCommand.id` is a client-generated UUID. Persist the entire command before
sending. Create/join use `roomEntry` scope; all other actions use `match` scope
with match ID, exact course reference, and the last confirmed revision.

| Action | Authoritative precondition / effect |
| --- | --- |
| `createRoom`, `joinRoom` | Authenticated session, nickname, room capacity of two; create chooses the initial shared algorithm/course |
| `selectAlgorithm` | Creator, lobby only; clears both confirmations and ready states |
| `confirmAlgorithm`, `setReady` | Lobby only; confirmation must match current selection; ready requires confirmation |
| `start` | Creator, both players ready/confirmed and verified at start; locks algorithm for the match |
| `confirmArrival` | Valid next stop and verified location/organiser proof; no client-authorised bypass |
| `chooseRoute` | After checkpoint one submission, one immutable branch choice per player |
| `submitAnswer` | Unlocked question, correct answer shape, arrival/prerequisites satisfied; at most one answer per player/question |
| `finish` | All three chosen checkpoints completed and finish arrival verified; 20 points once |
| `leave` | Explicit departure makes an unfinished match incomplete; network loss/backgrounding is not departure |

This table specifies server work for #6/#7; the scripted mock does not implement
these rules. Requests contain no client-supplied score or correctness.

For an authenticated principal, deduplicate by command ID **before** checking the
now-stale expected revision. The same ID and semantic payload returns its original
receipt without a second write or reward. A different payload with that ID fails
`idempotencyConflict`. Store command acceptance, submission uniqueness, reward
ledger entries, and revision atomically. Retain receipts for at least the lifetime
of the room/session recovery window, including create/join and explicit departure.
Validate the caller can read its original receipt; deduplication is not an auth bypass.

`CommandReceipt.acceptedRevision` is the original commit revision. A retried receipt
may carry an older snapshot. Ignore it if it is not newer than the current snapshot,
then refetch. `MatchSnapshot.supersedes` compares match, viewer, and revision; switch
matches/sessions explicitly and clear previous state. A match revision covers
private changes as well as public ones so learning-check/submission updates are
not lost. Realtime invalidates; it never supplies authoritative state.

After reconnect, foregrounding, or relaunch:

1. Restore the authenticated session and local `ReconnectState`.
2. Keep the last confirmed navigation visible, show reconnecting, and pause new
   authoritative actions. Cached route geometry does not guarantee offline map tiles.
3. Refetch an authorised snapshot and subscribe to invalidations. Refetch again
   after subscription establishment to cover the fetch/subscribe race.
4. Retry an uncertain pending command unchanged. On acceptance, clear that pending
   command. Do not create a new ID for an uncertain submission.
5. On a definitive `staleRevision` rejection with no accepted receipt, refetch and
   reconcile existing submissions/route state. Only issue a new command after
   confirming the original intent is still available. `alreadySubmitted` is not a
   request to award or submit again.

`MatchServiceError` carries a stable code, diagnostic message, optional latest
revision, and optional retry delay. Map codes to UI actions; do not parse the
message. Refresh for `staleRevision`, update course data for `incompatibleCourse`,
restore authentication for `unauthenticated`, and collect better location evidence
for arrival errors. Network failure/cancellation can leave an uncertain outcome;
keep the original command. Honour `retryAfterSeconds` for rate limiting. Adapter
transport errors may also be thrown, so callers must retain a generic error path.

## Fixture catalogue and use

Each `dijkstra/` and `aStar/` folder contains:

- `snapshots/lobby`, `practice`, `active`: confirmation/readiness, opening prediction,
  and an unlocked first challenge.
- `pendingFeedback`, `routeChoice`: private accepted answer, withheld shared reward,
  next-leg navigation or an unlocked route choice.
- `middleStandard`, `middleBonus`: locked branch, arrived player, eligible question.
- `sharedThirdStandard`, `sharedThirdBonus`: identical shared scenario after different branches.
- `feedbackReleased`, `waitingFinish`: shared release, a route to finish, and provisional standings.
- `finished`, `draw`, `incomplete`: winner, tied final scores, and explicit departure.
- `learningCheck`, `learningCheckAnswered`: new unscored graph and first-attempt record
  while the other player can continue.
- `reconnect.json`, `submit-command.json`, `submit-receipt.json`: uncertain submission,
  stable retry ID, and original acceptance.
- `public-pending.json`: the safe room projection, separate from private viewer data.
- `challenges/`, `trace.json`, `transfer-trace.json`: toy question and replay examples.

These are **independent screen scenarios**, not one linear chronological recording.
Alternative scenarios can share match IDs and revisions; never combine them into
one live room. `FixtureCatalog.commandExamples` and `commands/` cover every command
case. `invalidation.json` and `stale-revision-error.json` illustrate recovery payloads.

The fixtures contain answers only to the synthetic development questions. They
must not be used as a source of real scored match answers. Keep
`AlgorithmArenaFixtures` out of production app linkage/resources; the core product
contains no fixture data or answer bank.

```swift
import AlgorithmArenaCore
import AlgorithmArenaFixtures // preview/test target only

let command = ArenaFixtures.submissionCommand(.dijkstra)
let mock = ScriptedMatchService(
    initial: ArenaFixtures.snapshot(.active, algorithm: .dijkstra),
    transitions: [
        MockTransition(
            action: command.action,
            snapshot: ArenaFixtures.snapshot(.routeChoice, algorithm: .dijkstra)
        )
    ]
)
let service: any MatchService = mock
let receipt = try await service.send(command)
// Retrying `command` returns the same receipt without advancing again.
await mock.finish() // Ends subscriptions when the preview/test ends.
```

The mock checks scope, course, revision, immutable in-match algorithm, command
identity, and scripted action equality. It refuses unscripted actions. It does not
calculate scores, validate GPS, generate questions, or simulate a backend state
machine. Script additional scenarios explicitly; the live adapter implements the
same protocol with server responses. Subscribers receive an initial invalidation,
then the newest change. Cancel the observing task or call `finish()` to end a stream.
For Home, omit `initial` and script a create/join action returning a lobby snapshot.
A seeded mock already has a room; create a fresh instance for another Home scenario.

## Verification and handoff

From the repository root, with Swift 6 or later:

```sh
swift test --package-path Packages/AlgorithmArenaCore
swift run --package-path Packages/AlgorithmArenaCore export-contract-fixtures "$PWD/contracts/v1"
```

Tests cover public API encoding/decoding, course branch references, answer gating,
shared scenario identity, result totals, unscored learning, authored trace
consistency, mock retries/conflicts, stale revisions, subscription termination,
and byte-for-byte JSON drift. Export, inspect changes, and run tests whenever the
contract changes. Remove obsolete exported files when removing scenarios; tests
also reject leftover JSON. The CI workflow runs the package tests independently
of the iOS project.

- Munaikh: review the wire shapes and authority/privacy rules against #4–#8.
- owaini0: review app-facing models/service and mock usability before #10–#14.
- owaini0 owns adding the local package to the Xcode project and app adapters.
- Both: resolve review feedback before calling issue #3's review acceptance complete.

Production graph/heuristics, challenge content, live backend behaviour, and
physical-device GPS/AR remain separate acceptance work. These fixture tests do
not establish those outcomes.
