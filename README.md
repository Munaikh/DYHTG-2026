# Algorithm Arena · DYHTG 2026

[Hackathon demo guide and validation](docs/HACKATHON_DEMO.md) · [Plot Twist Duel backend](docs/DUEL.md)

A native SwiftUI app for learning Dijkstra and A* by making predictions, competing
with a friend, and watching searches unfold. Targets **iOS 17+** on iPhone and
iPad, using **Swift 6** and the Supabase Swift SDK.

## Three ways to explore

| Tab | Experience |
| --- | --- |
| **Learn** | Interactive lessons for both algorithms: predict the next node, update a cost, inspect the replay, and try a new graph. Progress saves on the device; no room or nickname is required. |
| **Play** | **Plot Twist Duel**: two players, three prediction rounds, private answers, shared animated reveals, and server-authoritative scores. A bridge closes in round two; a different network tests understanding in round three. |
| **Visualize** | A campus search laboratory with map/graph views, two prepared journeys, Dijkstra/A* selection, play/pause/step/scrub controls, adjustable playback speed, and a node-cost table. Close a path to trigger a detour or disconnect the destination, then compare route costs and expanded-node counts. |

Plot Twist Duel awards 100 points for each correct prediction, with no speed
bonus. Both players submit before answers or new scores are revealed, and both
continue before the next round starts. The host can start a rematch after the
results. [Duel contract, content, recovery, and backend runbook](docs/DUEL.md).

Learn and search calculations run locally. Play needs a network connection and
uses anonymous Supabase sessions. Map tiles come from MapKit. The campus paths
are an educational model awaiting an outdoor survey; Visualize does not request
location permission or provide walking directions.

## Welcome and profile

The animated welcome tour introduces these same three tabs. Open your avatar in
any tab to edit your nickname, choose one of eight avatars, pick a profile color,
or replay the welcome tour. Edits are drafts until **Save profile**; **Cancel**
discards them. Profiles save locally, and a nickname change applies to the next
duel you create or join. Existing room identities and anonymous sessions stay intact.

## Run the app

Use Xcode with a Swift 6 toolchain and an installed iOS Simulator runtime.

1. Open `DYHTG-2026.xcodeproj` and let Xcode resolve its Swift package dependencies.
2. Select the `DYHTG-2026` scheme and an iPhone or iPad simulator.
3. Press **Command-R**.

The entry point is [`DYHTG2026App.swift`](DYHTG-2026/App/DYHTG2026App.swift);
[`RootView.swift`](DYHTG-2026/App/RootView.swift) owns the three-tab shell.
For a physical device, select your development team under Signing & Capabilities
and use a bundle identifier available to that team.

Build for the simulator from the repository root:

```sh
xcodebuild \
  -project DYHTG-2026.xcodeproj \
  -scheme DYHTG-2026 \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/algorithm-arena-build \
  CODE_SIGNING_ALLOWED=NO build
```

The app uses the configured development backend in
[`ArenaBackend.swift`](DYHTG-2026/Live/ArenaBackend.swift). Only a publishable key
belongs in the client. See [`supabase/client-config.json`](supabase/client-config.json)
and [the backend setup guide](docs/SUPABASE.md#project-and-configuration) when
working with another environment. Keep the committed `Package.resolved` file so
Xcode resolves the same SDK versions.

## Test

Run the Foundation-only package tests, client recovery checks, and independent
content verifiers:

```sh
swift test --package-path Packages/AlgorithmArenaCore
bash scripts/test_duel_store.sh
python3 -B scripts/verify_search_fixtures.py
python3 -B scripts/verify_learning_content.py
```

These cover canonical Dijkstra/A* traces, heuristic validation, lesson content,
prepared campus closures and unreachable destinations, duel wire contracts, and
client recovery. The store harness exercises the production `DuelStore` with a
controlled transport, including lost responses, persistence, stale revisions,
cancellation, and concurrent actions. The Xcode scheme currently has no XCTest
bundle; a successful app build is separate from these executable checks.

For real Auth/PostgREST multiplayer tests, use **Node 22+** and a running local
Supabase stack with the committed migrations:

```sh
node scripts/test_supabase_duel.mjs
```

To test the configured hosted development project and decode its actual response
corpus with Swift:

```sh
DUEL_WIRE_PATH=/tmp/duel-hosted-wire.json node scripts/test_supabase_duel.mjs --remote
DUEL_WIRE_PATH=/tmp/duel-hosted-wire.json swift test \
  --package-path Packages/AlgorithmArenaCore --filter DuelContractTests
```

The hosted test creates anonymous test identities and rooms. It exercises both
algorithms, racing and duplicate submissions, hidden answers/scores, wrong
answers, reconnect, all three rounds, results, rematch, and leave. See
[the duel verification notes](docs/DUEL.md#verification) for setup and scope.

For a manual multiplayer check, run the app on two simulators or devices. Create
a duel on one, join using its six-character code on the other, ready both
players, and start as the host. Check that one player's locked answer stays
private until the other submits, then complete all three rounds and a rematch.
Also relaunch during an active room to check recovery. A terminal opponent is
available for one-simulator development:

```sh
node scripts/duel_partner.mjs ROOMCODE --auto
```

It uses a separate anonymous identity and the public graph state. It does not
replace checking the UI on both clients. Review both lessons, the map and graph,
closures, no-route recovery, larger text, and Reduce Motion on the target devices.

## Code and content

- [`DYHTG-2026/Learn`](DYHTG-2026/Learn): lessons and local progress.
- [`DYHTG-2026/Duel`](DYHTG-2026/Duel): multiplayer UI, transport, and persistent command recovery.
- [`DYHTG-2026/Visualization`](DYHTG-2026/Visualization): campus experiments and search presentation.
- [`Packages/AlgorithmArenaCore`](Packages/AlgorithmArenaCore): Foundation-only search engine, traces, routing, public lesson catalog, and wire models.
- [`content/duel/v1/server`](content/duel/v1/server): server-only authored duel rounds and answer keys; excluded from the app target.
- [`supabase/migrations`](supabase/migrations): additive database migrations, including the indoor duel mode.

The public lesson catalog is separate from private multiplayer answer banks.
`AlgorithmArenaLearning` contains historical question-bank authoring data and is
not linked into the production app. Detailed references:
[search and routing](docs/SEARCH.md), [shared contracts](contracts/README.md),
[learning content](docs/LEARNING.md), and [Plot Twist Duel](docs/DUEL.md).

## Historical outdoor plan

The original concept used campus checkpoints, arrival verification, route
choices, and AR. Its source and backend remain in the repository as historical
work; those flows are **not part of the current three-tab app**. The active
multiplayer mode is the indoor Plot Twist Duel, and the map's role is algorithm
visualization.

The [original MVP plan](docs/PLAN.md), [two-person work breakdown](docs/WORK_BREAKDOWN.md),
[outdoor backend runbook](docs/SUPABASE.md), and
[Gilmorehill survey candidate](docs/COURSE_SURVEY.md) document that earlier scope.
Their checkpoint requirements and implementation-status notes should not be used
as the current product specification. The legacy backend suites remain available
as `scripts/test_supabase_lobby.mjs` and `scripts/test_supabase_match.mjs`.

The rebased Pathfinder branch also retains experimental friend-battle and road-search
source. Those routes are not exposed by the active three-tab shell; its older
[expansion notes](docs/EXPANSION.md) are historical, not current setup requirements.
