# Algorithm Arena — native game experience

## Open and run

This change lives in the existing Desktop `DYHTG-2026` repository on branch
`feature/algorithm-arena-gamification`. Open `DYHTG-2026.xcodeproj`, select the
existing `DYHTG-2026` scheme and an iPhone Simulator, then press Command-R.
The app remains Swift 6 / SwiftUI, with an iOS 17 deployment target and the
original bundle identifier. No web view or separate application was created.
For a physical iPhone, select the team's signing identity in Xcode as before.

The Xcode synchronized source folder automatically includes the new Swift files.
The existing app target additionally links the local `AlgorithmArenaProgression`
package product. It does **not** link the server-private
`AlgorithmArenaLearning` answer bank.

## Existing functionality retained

Before editing, the repository already contained the native campus game,
MapKit campus geometry and walking paths, arrival checks and organiser fallback,
AR replay, Dijkstra/A* engines, challenge and feedback views, match results,
and a real Supabase adapter with anonymous sessions, RPCs, Realtime invalidation
and persisted reconnect state. These implementations remain the source of truth.
The synthetic solo service remains clearly distinguished from live rooms.

The original specification in `docs/PLAN.md` scoped competitive play to Dijkstra
and A*. The requested indoor education and gamification are an **explicit MVP
expansion**. They do not extend the two-case `AlgorithmKind` wire enum, alter
SQL, change multiplayer payloads, or change the shared-feedback gate.

## Native experience implemented

- Home, Learn, Play, Quests and Profile tabs, with a direct Continue learning action.
- Five algorithm modules, each with three lessons and three practice activities:
  15 lessons and 15 different, stable-ID practice activities in total.
- Each activity asks a next-point prediction from an actual algorithm trace.
  Available answers, costs, correct answers and worked explanations use that trace.
  Learners can change a selection before checking, retry mistakes without XP
  penalties, request three progressive hints, and watch the search step by step.
- BFS/DFS queue/stack order is shown explicitly; Dijkstra/A*/Greedy choices include
  their relevant costs. Detailed graph connections and costs are available as text.
- Replay supports previous, next, restart, play and pause. Playback cancels when
  dismissed. Highlighted edges and discovered routes reflect recorded search events.
- Six claimable quests, eleven collectible titles, and six achievements.
- Local nickname, equipped title, learning completion, reward ledger, attempts,
  hint usage, preferences and real-match learning milestones persist across launches.
- Beginner guide, Reduce Motion, larger answer controls, device/light/dark
  appearance, Dynamic Type, labelled controls, selection indicators, graph text
  alternatives and spoken reward announcements.

The optional Bellman–Ford module is deliberately outside this implementation.
Lessons are short authored graph predictions, not an open-ended graph editor or
an AI tutor. Adding more authored graphs and concepts is a future content task.

## Architecture and algorithms

`Packages/AlgorithmArenaCore/Sources/AlgorithmArenaProgression` contains pure,
Foundation-only business logic:

- `StudyAlgorithm.swift`: independent indoor algorithm enum and deterministic search.
- `StudyCatalog.swift`: versioned content, graph generation and trace-derived questions.
- `LearningProfile.swift`: Codable state, level curve, quests, titles and achievements.
- `LearningJourney.swift`: validated learning commands, rewards and atomic persistence.

Dijkstra and A* reuse the existing `SearchEngine`, including graph validation and
heuristic requirements. BFS uses a FIFO frontier. DFS uses a LIFO frontier,
prioritising the current deeper branch and never reopening settled points.
Greedy chooses the smallest h, then node ID. Traversals and adjacency ties are
deterministic. BFS lessons use unit-weight graphs. DFS and Greedy explicitly
explain their lack of a shortest-path guarantee. The weighted teaching graph
shows Greedy returning cost 15 while Dijkstra/A* return cost 13. The A* graph
uses consistent, admissible estimates derived from shortest distances to the goal.

`DYHTG-2026/Adventure` contains focused native services, design components and
feature views. `LearningStore` adapts the pure commands to Swift Observation and
only publishes earned progress after a successful save. Existing graph rendering
is reused with an optional indoor cost display. Existing competitive challenge
logic and answer derivation remain separate.

## Interaction sounds and motion

Main learning buttons, algorithm cards and answer choices have a short press
animation; selection and answer feedback transition gently. System Reduce Motion
and the saved app preference remove these added motion effects.

Optional soft tap, success, level-up and gentle retry cues are generated locally
as short mono PCM sounds and played with AVAudioPlayer. The audio session uses
`ambient`, respects Silent Mode/device volume, and mixes with music and VoiceOver.
No microphone, network request or external sound asset is needed. Disabled
buttons do not play. Rewards chime only after progress saves successfully.
Sounds stop when the app becomes inactive or the setting is turned off.

Profile → Sound includes Button sounds and a sample button. This preference is
saved under `arena.soundEffectsEnabled` in the existing app's UserDefaults,
without changing or invalidating the existing learning-save schema. Sounds are
on initially and are never required to understand feedback. The native build
with these interaction changes passes. Physical speaker output and the hardware
Ring/Silent switch should also be checked on an iPhone before release.

## XP, quests and cosmetic rewards

Learning XP is **not competitive match points**.

| Event | XP | Duplicate prevention |
| --- | ---: | --- |
| First correct completion of a lesson | 50 | Versioned activity ID |
| First correct completion of a practice puzzle | 20 | Versioned activity ID |
| Complete all three lessons in a module | 100 extra | Algorithm module key |
| First steps quest | 50 | Claimed quest ID |
| Node hunter quest | 100 | Three distinct practice completions |
| Dijkstra module quest | 150 | Three Dijkstra lessons |
| Two practice puzzles without hints quest | 100 | Stored first-completion hint records |
| Learn across three algorithms quest | 200 | Distinct learned algorithms |
| Campus challenger quest | 50 + cosmetic achievement | One final real two-player match |
| Finish an eligible live campus match | 60 | Match ID |

Wrong predictions and hints award no XP and deduct none. Replaying a solved
activity awards none. Mistake/hint records for the original practice completion
remain unchanged by later review. Quests require an explicit claim, with ready,
locked and claimed states. No daily streaks, paid hints or timed rewards exist.

Level L starts at `50 × (L − 1) × L` XP: level 2 at 100, level 3 at 300,
level 4 at 600. The XP bar and reward notice show progress and level-ups.

Titles expose their exact requirements. First lesson unlocks Graph rookie;
BFS/DFS/Dijkstra/A* modules unlock their associated titles; practice and quest
milestones unlock further titles. Algorithm champion and First victory require
a real released win. Titles are cosmetic and can only be equipped after unlock.

A live completion requires a final snapshot, two finished participants, a viewer
who is a room member, and a winner/draw result. Incomplete matches and the
synthetic solo mode cannot earn the campus milestone or championship.
These are device-local acknowledgements of server match results, not a new
server-authoritative ranking or account system.

## Persistence and privacy

The app saves Codable JSON atomically to its sandbox:
`Application Support/AlgorithmArena/learning-progress-v1.json`.
XP, levels and quest progress derive from a single reward/completion history,
avoiding multiple competing counters. Saves contain a schema version. An
unreadable, invalid or future-version save produces a visible retry error and is
not silently reset. Failed writes do not publish XP or unlocks.

The original nickname UserDefaults key is shared with campus entry. Indoor
learning does not authenticate online, collect location, or create child profiles.
The existing campus service continues using Supabase. Learning progress is local
to an installation; cloud sync, reinstall recovery, data migration to future
schemas and account-linked anti-tamper enforcement are not implemented.

## Campus presentation changes

- Campus entry has short instructions, expandable details, a Close action and a nickname shared with the learning profile.
- Scoreboards now name match points and show the selected route's 80/100 maximum.
- The compact player comparison adapts to narrow layouts and long nicknames.
- Route choice states the 20/40-point middle rewards and 80/100 totals.
- Incomplete answer fields explain why Submit answer is disabled.
- Private submissions and waiting-for-both feedback are explained explicitly.
- Results have outcome-specific symbols and a short Reduce Motion-aware reveal.
- Map-follow and feedback transitions respect system/app Reduce Motion preferences.

Authoritative scoring is unchanged: 20 first + 20 standard / 40 bonus middle +
20 third + 20 finish; maxima 80/100; walking speed 0. Shared answers remain
unavailable until both submit. No new hints were added to scored multiplayer.

## Verification

Commands used from the repository:

```sh
swift test --package-path Packages/AlgorithmArenaCore
python3 scripts/verify_search_fixtures.py
python3 scripts/verify_learning_content.py
xcodebuild -project DYHTG-2026.xcodeproj -scheme DYHTG-2026 \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGN_IDENTITY=- build
```

The pure package suites cover original contract/scoring/privacy behavior plus
all five indoor algorithms, input-order determinism, trace-derived answers,
all 30 completions, level thresholds, module bonuses, invalid identifiers,
wrong answers, hints, duplicate claims/completions, locked title rejection,
real versus synthetic match eligibility, persistence, damaged saves and future
schema rejection. The independent Python checks verify 22 search traces and
12 authored competitive challenges without exposing private answer banks.

The existing configured live backend was tested with
`scripts/test_supabase_lobby.mjs --remote`, using the existing public client
configuration kept in process memory. All 13 lobby integration checks passed:
room membership, retries, concurrent joins, Realtime reconnection, RPC access
control, safe snapshots and private-table restrictions. No migrations or backend
deployments were performed.

Native Simulator checks include first-lesson selection/checking, actual replay
playback, XP notification, quest claim and level-up, title unlock/equip, preference
changes, dark appearance and persistence after terminating/relaunching the app.
The app was also launched on the smaller iPhone 17e Simulator. Home was inspected
at its standard text size and at accessibility extra-extra-large. XP/level labels
stack vertically at accessibility sizes. In practice, a hint was requested, an
incorrect prediction received graph-specific feedback, and the corrected answer
saved 20 XP. Closing the activity, returning to the library, and returning to Play
worked. The original campus Create/Join/Solo controls remain reachable. A real room was
also created through the native Simulator app, reaching the server-backed lobby
with the correct nickname and algorithm selection. The temporary room was left
after this check.

Use normal local signing for Simulator integration tests (`CODE_SIGN_IDENTITY=-`).
An earlier build with signing disabled compiled but could not persist the
Supabase anonymous session in secure storage, producing a misleading Session
Expired message. The normally signed build successfully created a live room.
No authentication workaround or insecure token storage was added.

Final automated results: 53 Swift test functions passed (10 progression, 8 authored
learning, 35 core/contract, with additional parameterized cases). The iPhone 18 Pro
Simulator build succeeded. One build-tool notice says App Intents metadata was
skipped because the app has no AppIntents dependency; it is not a compilation error.

## Integration with current main

Before publishing the review branch, the newer organiser QR check-in commit
`1834457` from main was integrated into this feature branch. The campus entry
conflict was resolved by retaining both the clearer entry/Close action and the
team's Organiser Tools menu and sheet. QR approval, organiser screens and the
updated check-in plumbing remain intact. This integration changes only the
feature branch, never main.

## Team review and remaining release work

Ready for team review: native navigation, five indoor algorithms, trace-driven
lessons/practice, progression, quest claims, cosmetic collections, native local
saves, accessible alternatives and additive campus presentation changes.

A complete two-device campus match, organiser credentials, physical GPS arrival
checks, surveyed building/path accuracy and AR camera tracking still require
physical-device integration testing. The course remains the existing Gilmorehill
survey candidate, not a verified Google Maps routing dataset. It must be surveyed
before navigation release. Child-facing online multiplayer also needs the
appropriate team privacy/safety review before release.

The pre-existing local `Package.resolved` modification was preserved. Changes
are isolated on the feature branch for team review. Main is unchanged; merging
and deployment require separate approval.
