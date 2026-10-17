# Authored learning content

Implementation handoff for [#5](https://github.com/Munaikh/DYHTG-2026/issues/5).
The `AlgorithmArenaLearning` product contains the immutable `2026-10-17.1` bank:
six questions per algorithm, worked feedback, tested search replays, and private
first-attempt assessment. It depends only on `AlgorithmArenaCore` and Foundation.
The app continues to depend only on the client contracts; screen implementation
belongs to #11 and authoritative persistence/unlocking/scoring belongs to #7.

## Questions and answer fixtures

All graphs are authored teaching examples, independent of the walking course.
Changing a course, player, or middle branch cannot alter a shared question.
Each slot has its own fixed graph and ID, so an earlier released replay does not
expose a later question. The final graphs have a different topology and start
partway through a search, rather than repeating the opening exercise.

| Slot | Dijkstra solution | A* solution | Points | Feedback |
| --- | --- | --- | ---: | --- |
| Opening practice | Q: g=4, rather than R: g=7 | Q: f=6+1=7, rather than R: f=2+6=8 | 0 | Immediate, self only |
| Checkpoint one | M: g=3, rather than N: g=6 | A: f=3+4=7, rather than B: f=8+1=9 | 20 | After both submissions |
| Standard middle | W: min(7, 2+3)=5 | E: min(9, 3+2)=5; f=5+3=8 | 20 | Immediate, self only |
| Bonus middle | L: min(6, 2+1)=3, then M: min(9, 3+2)=5 | E: min(8, 3+2)=5, then F: min(12, 5+3)=8 | 40 | Immediate, self only |
| Checkpoint three | S → A → C → G: 2+2+3=7, versus 1+10=11 | J → K → M → Z: 3+2+3=8, versus 2+11=13 | 20 | After both submissions |
| Final learning check | W: g=4, versus Y: g=6 and Z: g=9; lowest frontier g | R: f=7+1=8, versus Q: f=4+5=9 and T: f=12+0=12; lowest frontier f | 0 | Immediate, self only |

For Dijkstra, the opening/first diagrams deliberately put the more expensive
frontier node nearer to the goal. The prompt states that proximity in words too,
so this misconception is accessible in the node-list presentation. Edge costs,
not the diagram's geometry, determine g. Relaxation replaces an existing cost
only with a cheaper candidate; replays also show rejected worse candidates.

For A*, practice distinguishes g alone from f. Checkpoint one distinguishes h
alone from f. The final check tests both misconceptions on the same frontier:
Q has the lowest g, T the lowest h, and R the lowest f. Feedback defines g, h
and f, and distinguishes estimates from confirmed cost. Route comparison sums
edge costs and shows an expanded branch absent from the final route. It makes
no promise that A* always expands fewer nodes.

The bonus question starts **before both required updates**. The improved
intermediate g is not already filled in. It requires two additions and two
cheaper-path comparisons, then asks for the final target g. Standard and bonus
replace one another; `matchChallenges(algorithm:branch:)` returns exactly first,
one middle, and third. With the separate 20-point finish award, maxima remain
80/100. Practice and the final check never award competition points.

## API and release boundary

```swift
import AlgorithmArenaCore
import AlgorithmArenaLearning // server or isolated preview/test tooling only

let content = try LearningCatalog.challenge(.first, algorithm: .aStar)
let unlockedPrompt: ChallengeDefinition = content.definition
// Deliver this prompt only after the server verifies this player's prerequisites.

let first = LearningSubmission(
  playerID: "alex", challengeID: content.definition.id, answer: .node(nodeID: "B"))
let pending = try content.feedback(
  for: "alex", participants: ["alex", "sam"], submissions: [first])
// .pending(challengeID: ...) contains no correctness, key, award or replay.

let second = LearningSubmission(
  playerID: "sam", challengeID: content.definition.id, answer: .node(nodeID: "A"))
let released = try content.feedback(
  for: "alex", participants: ["alex", "sam"], submissions: [first, second])
// Both answers, correct arithmetic, full trace and per-worked-step replay indices.
```

`feedback` is a projection of **already accepted, persisted submissions** for an
authenticated viewer. It validates the two distinct participants, membership,
question IDs, submission uniqueness, answer shape and offered options. Wrong
but valid answers release explanations and permit progression just like correct
answers. Before their own submission a viewer gets no feedback. Once they submit
a shared question, they get only pending feedback until both have submitted.
Immediate questions expose only the viewer's answer, even if both are supplied.
Every valid answer option, including each node/reason combination and incorrect
numeric answers, receives concise feedback, worked arithmetic and a complete replay.

The backend must enforce authentication, arrival, branch lock, question unlocks,
one submission, and idempotency **before** calling this projection. Award ledger
writes, shared score release and match revisions must commit atomically in #7.
Calling this helper is not a transaction or proof of authorisation. Never place
`LearningChallenge`, evaluations or full traces in `PublicMatchState`, command
responses before release, or Realtime payloads; Realtime carries invalidations.

`learningCheckRecord(answer:answeredAt:firstAttempt:)` records node and reason
correctness separately. Supplying an existing record for this question returns
it unchanged, including its timestamp. Store the first record transactionally,
privately and independently of the score/result. The check never blocks the
other player's finish or the final result. Retries cannot replace the original
attempt. A matching node with an incorrect reason remains a partial result.

## Files and client compatibility

- [`content/learning/v1/prompts`](../content/learning/v1/prompts) contains 12
  client-safe definitions. Serve only the individual currently unlocked prompt,
  never the entire directory (including future/unchosen branch questions).
- [`content/learning/v1/server`](../content/learning/v1/server) contains 12
  server-private answer fixtures, worked arithmetic, replay references, and full
  engine traces. Import through private server tooling/storage. Do not package
  them as public assets, app resources, a public database table, or CDN files.
- `AlgorithmArenaLearning` is a separate target/product with no dependency from
  core or the app. It can be imported by isolated preview/test targets to build
  released/pending examples through the same projection. Never link the answer
  bank into a live app. Existing synthetic `AlgorithmArenaFixtures` remain
  unchanged to preserve the #3 mock handoff.

Two additive optional fields extend v1 without changing existing JSON:

| Field | Meaning and fallback |
| --- | --- |
| `ScenarioNode.position` | Normalised diagram x/y in 0...1, y down. Illustrative layout only, not GPS, units or heuristics. Respect it for the proximity exercises; a node list also has the textual prompt. Existing consumers may use their layout when absent. |
| `ReleasedFeedback.workedStepTraceIndices` | One nonempty array per `workedSteps` entry, indexing the full `trace.steps`. Use these to focus a worked step's replay; when absent, offer the existing full replay controls. |

The client prompt contains only the presented search snapshot. The private
`presentedStepIndex` and future steps are withheld until release. Each reference
uses the exact corresponding engine event, including accepted/rejected relaxations
and the expanded branch omitted from the final route. Full replay remains
available for correct and wrong responses with the same 2D/AR trace contract.
Show g only for Dijkstra; show g, h and f for A*. An omitted g remains undiscovered,
not zero. IDs, content version and scenario source/goal are immutable; publish
changed content under new IDs/version after release.

## Verification

From the repository root:

```sh
swift run --package-path Packages/AlgorithmArenaCore export-learning-content "$PWD/content/learning/v1"
swift test --package-path Packages/AlgorithmArenaCore
python3 -B scripts/verify_learning_content.py
python3 scripts/verify_search_fixtures.py
```

Swift tests independently calculate answers from question states/edges, check
bonus two-step arithmetic, every node/route/reason combination, shared-gate
privacy for correct and wrong answers, self-only immediate feedback, invalid
inputs, branch replacement, first-attempt preservation, partial understanding,
replay references and byte-for-byte exports. Existing contract tests also verify
old JSON compatibility. Python independently reproduces all 12 full traces,
checks heuristic admissibility/consistency with an all-pairs oracle, recalculates
answers and displayed arithmetic, and verifies prompt privacy. CI runs both.

This establishes authored-content correctness and projection behaviour. Live
two-player persistence/privacy and observed student understanding remain the
acceptance work in #7/#8 and #15; SwiftUI presentation remains #11.
