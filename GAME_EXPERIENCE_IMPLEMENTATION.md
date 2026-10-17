# Gamified learning in Plot Twist

PR #31 (`95442e1`) supplies the five-algorithm learning catalog and local
progression model. This integration adapts those features to the Plot Twist app
at `a66b65a`, rather than replacing its multiplayer, profile, or graph renderer.

## Included and adapted

- BFS, DFS, Dijkstra, A*, and Greedy: three lessons and three practice puzzles
  each, for 15 lessons and 15 practices. Questions and explanations come from
  deterministic search traces, with hints, retry, and replay controls.
- Saved learning XP and levels, six claimable quests, eleven cosmetic titles,
  and six achievements. Rewards are recorded once in a persisted ledger.
- A Home dashboard inside Learn, with Continue learning, lesson/practice
  libraries, beginner guidance, and quests. Practice is also available from Play.
- Titles, achievements, learning progress, and beginner guidance inside our
  existing profile. The nickname, avatar, color, Save/Cancel behavior, dark-mode
  icon fix, and welcome replay remain consistent across all three tabs.
- The shared mint/ink Arena palette, buttons, cards, and refined graph renderer.
  BFS shows depth, DFS shows visit state, and Greedy shows its estimate; Dijkstra
  and A* keep the established cost presentation.
- Plot Twist completion/win milestones replace campus-match rewards. Incomplete
  games do not earn completion XP. Learning rewards never affect match scores.

## Kept from Plot Twist

The three primary tabs remain **Learn / Play / Visualize**. Home and Quests are
learning destinations, and the avatar opens the shared Profile from every tab.
Play remains the indoor, three-round Plot Twist Duel. Visualize remains the
educational map/graph laboratory, with closures, detours, and no-route recovery.

The original Dijkstra/A* guided lessons remain under **Duel warm-ups**, including
all prior saved progress. They are separate content from the new thirty
activities, so previous completions are not falsely marked as new completions.

## Excluded from PR #31

- The competing five-tab shell and old campus multiplayer entry points.
- Changes to checkpoint matches, route rewards, organiser check-ins, historical
  results, and the old Home screen.
- The duplicate nickname/profile editor and its separate styling.
- Optional sound effects and additional appearance/control settings.
- The older graph-rendering changes that would undo the recent label and arrow
  refinements.

No SQL migration, server scoring, private answer bank, location requirement, or
multiplayer wire contract changes are included.

## Persistence and rematches

`AlgorithmArenaProgression` is a Foundation-only package product. The app links
this public learning catalog, not the server-private `AlgorithmArenaLearning`
answer bank. `LearningStore` publishes rewards only after the atomic local save
succeeds. A damaged or future save is preserved and reported instead of silently
reset. The existing nickname preference is authoritative.

A duel room is reused for rematches. A persisted room/revision cursor opens a
new reward cycle only after observing a later active game; repeated finished
snapshots and post-game updates cannot grant XP twice. If the app misses an
entire rematch, the current server payload has no distinct game ID, so the
client conservatively avoids an ambiguous second reward. Saved XP and titles
are local cosmetics, not an online leaderboard.

## Verification

Run the package suite and existing contract checks:

```sh
swift test --package-path Packages/AlgorithmArenaCore
bash scripts/test_duel_store.sh
bash scripts/test_learning_store.sh
python3 -B scripts/verify_search_fixtures.py
python3 -B scripts/verify_learning_content.py
```

Build and run the signed iOS Simulator app using the existing Xcode scheme.
Check a wrong answer, hint, correct answer, next lesson, practice, replay,
quest claim, title equipment, profile cancellation, restart persistence,
Plot Twist multiplayer, and the existing Visualize controls. Native UI checks
are separate from Foundation package tests. Device-only behavior remains outside
simulator coverage.

Integration checks passed: 73 package tests (including the 90-snapshot hosted
duel corpus), 7/7 production LearningStore checks, 12/12 DuelStore recovery
checks, 15 hosted multiplayer checks, 22 golden search traces, and 12 authored
competitive challenges. Signed simulator builds pass. Native checks include
wrong-answer retry, hints, saved XP, replay play/pause, next-lesson reset,
quest claiming, title equipment, and progress surviving relaunch.
