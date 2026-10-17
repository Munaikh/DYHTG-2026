# DYHTG-2026

A native Swift 6 / SwiftUI educational game for iOS 17 and later.

## Algorithm Arena planning

The campus game supports two players using Dijkstra or A*. The native learning expansion adds indoor lessons, practice, XP, quests, titles and saved progress for five algorithms.

See [game experience implementation and validation](GAME_EXPERIENCE_IMPLEMENTATION.md).

- [MVP implementation plan](docs/PLAN.md): learning outcomes, gameplay, architecture, course, AR and acceptance criteria.
- [Two-person work breakdown](docs/WORK_BREAKDOWN.md): assigned GitHub issues, blockers, ownership and integration handoffs.
- [Part 1: algorithms, learning content and backend](https://github.com/Munaikh/DYHTG-2026/issues/1) — Munaikh.
- [Part 2: native iOS experience, navigation and AR](https://github.com/Munaikh/DYHTG-2026/issues/2) — owaini0.

## Run

1. Open `DYHTG-2026.xcodeproj` in Xcode.
2. Select the `DYHTG-2026` scheme and an iOS simulator.
3. Press Command-R to build and run.

The app starts in `DYHTG-2026/App/DYHTG2026App.swift`. Its existing root coordinates the new learning tabs and the original campus lobby, match and results screens. New Swift files under `DYHTG-2026` are automatically included by the Xcode synchronized folder.

For a physical device, choose your development team in Signing & Capabilities
and replace the starter bundle identifier `com.example.DYHTG2026` with your own.

Xcode resolves the existing Supabase Swift dependency and the local AlgorithmArenaCore package. Indoor learning does not need a backend or GPS.

## Shared contracts

The Foundation-only Swift package in `Packages/AlgorithmArenaCore` defines the
app/backend boundary. [Contract documentation and JSON fixtures](contracts/README.md)
cover both algorithms, private feedback gates, mock services, and recovery.

Run its tests independently of the app:

```sh
swift test --package-path Packages/AlgorithmArenaCore
```

The separate `AlgorithmArenaFixtures` product supplies synthetic development data.
The core now includes deterministic Dijkstra/A*, replay traces, and
[dynamic routing between any two selected campus points](docs/SEARCH.md).
`CampusRouter` builds start/goal nodes on a supplied versioned pedestrian network;
it does not require the JMS/Library endpoints or game checkpoints.

The included [Gilmorehill survey candidate](docs/COURSE_SURVEY.md) is awaiting an
outdoor survey and is not suitable for navigation. Xcode/map selection integration
remains with the iOS track. Check the independent Python fixture verifier with:

```sh
python3 scripts/verify_search_fixtures.py
```

The [authored learning bank](docs/LEARNING.md) supplies all six question slots for
each algorithm, worked explanations, replay references and first-attempt checks.
Client-safe prompts and server-private answer fixtures live separately under
`content/learning/v1`. The `AlgorithmArenaLearning` product is for server/authoring
tools and isolated previews/tests; keep it out of the production app.

```sh
python3 -B scripts/verify_learning_content.py
```

## Supabase multiplayer backend

The [Supabase lobby backend](docs/SUPABASE.md) implements contract-v1 room
creation/join, anonymous player identity, algorithm agreement and readiness,
member-only snapshots, idempotent commands and safe Realtime invalidations.
Reproducible configuration, migrations, security tests and integration tests live
under `supabase/` and `scripts/test_supabase_lobby.mjs`. The same backend now
validates the complete match, arrivals, locked route choices,
private submissions, gated feedback and exactly-once scoring (#7). Run the focused
match reliability test with `node scripts/test_supabase_match.mjs`. The runbook
also covers concurrency/privacy checks, Swift/server parity, organiser setup,
recovery and demo reset (#8). The existing iOS Supabase adapter remains in `DYHTG-2026/Live`; the learning expansion reuses it.
