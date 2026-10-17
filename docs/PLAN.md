# Algorithm Arena: learning-first iPhone MVP

Agreed 17 October 2026. This is the implementation specification, not a claim that the app is complete.

## Goal and learning outcomes

Two students start at the same campus location, choose the same pathfinding algorithm, and complete a shared outdoor course. Algorithm knowledge and decisions determine the score; walking speed earns nothing. The primary success criterion is learning.

After a match, a player should be able to:

- Explain why the selected algorithm expands a particular frontier node.
- Update a neighbour's tentative path cost using the current path and an edge cost.
- Distinguish the algorithm's search from the final route that they physically walk.
- Apply the selection rule to a new graph and explain their reasoning.
- In an A* match, distinguish cost so far (`g`), estimated remaining cost (`h`), and selection priority (`f = g + h`).

Audience: introductory computing students. Explanations use plain language, the actual graph values, and worked steps. Learning content is authored and deterministic; runtime AI generation is outside this MVP.

## Fixed scope

| Area | MVP decision |
| --- | --- |
| Platform | Native SwiftUI iPhone app, iOS 17+, Swift 6 |
| Players | Exactly two players in a room, using nicknames and anonymous sessions |
| Algorithms | Dijkstra and A*, with one shared selection locked for the whole match |
| Course | One prepared Gilmorehill pedestrian course, approximately 500–800 m |
| Start / finish | Outside James McCune Smith Learning Hub / outside the University Library |
| Stops | Exactly three checkpoints per player; standard or bonus middle checkpoint |
| Duration | Approximately 10–20 minutes |
| Navigation | Campus graph, route line, current location, next checkpoint, scores, and opponent progress |
| AR | Optional surface-anchored search replay at a stationary checkpoint |
| Backend | Dedicated Supabase project in London, under the existing DYHTG organisation |
| Design | Native outdoor game: deep green accent, neutral surfaces, clear graph hierarchy |

Accounts, persistent leaderboards, BFS, larger matches, additional courses, indoor navigation, LiDAR mapping, continuous AR navigation, opponent interference, paid hints, and mid-match algorithm switching are out of scope. Both algorithms are available, but there is no mandatory cross-algorithm comparison within a match.

## Complete match flow

1. **Home:** enter a nickname and create or join a room using a shareable code.
2. **Lobby:** the creator selects Dijkstra or A*. Both players confirm it and become ready. Changing the algorithm clears both ready states. Verify both players at the shared start before starting.
3. **Opening prediction:** briefly state the rule and ask one unscored prediction. Show feedback and replay, then reveal the first walking route. Keep this short rather than adding a separate tutorial funnel.
4. **Checkpoint one:** confirm arrival, stop, and predict the next node to expand. Submit once for up to 20 points.
5. **Route choice:** independently choose the standard or bonus middle checkpoint. Show distance, difficulty, and reward before locking the choice; do not expose its challenge before the choice is locked.
6. **Middle checkpoint:** calculate an updated cost. The standard challenge awards up to 20 points; the bonus replaces it with a harder calculation worth up to 40 points and approximately 50–100 m extra walking.
7. **Checkpoint three:** complete the shared route-cost comparison challenge for up to 20 points, then walk to the finish.
8. **Finish and understanding check:** reaching the finish after all three chosen checkpoints awards 20 points. Offer one unfamiliar graph question plus a reason choice, with feedback. Record first-attempt understanding separately from the competition score. This check does not delay the other player's result.
9. **Results:** once both finish, show winner or draw, checkpoint points, each route choice, and an accessible review of decisions and replays. The first finisher sees a waiting state with provisional standings.

An incorrect scored answer earns zero but still unlocks progression. A retry, repeated tap, or reconnect never creates a second submission or reward. Explicit departure makes the match incomplete rather than awarding a normal score-based win. Temporary disconnection or backgrounding is not departure.

## Learning content and feedback

### Dijkstra

Teach tentative distance from the start, choosing the lowest-cost unsettled node, and replacing a neighbour's tentative distance only when the new path is cheaper. Include a case where a node geographically closer to the goal is not the next selection.

### A*

Teach `g` as cost so far, `h` as an estimate of remaining cost, and `f = g + h` as the frontier priority. Explain that the estimate is not a confirmed walking cost and that choosing the smallest `h` alone is not A*. Include a case that exposes that misconception. Do not promise A* always expands fewer nodes.

### Feedback contract

- Show the submitted answer, the correct reasoning, the real arithmetic, and the relevant search steps for correct and incorrect answers alike.
- At shared checkpoints one and three, withhold correctness, awarded points, explanation, and replay until both players submit. The first player can continue to the next leg while waiting.
- Mark pending shared feedback clearly, keep it accessible from the map, and notify in-app when it unlocks without forcing a screen change while walking.
- Alternative middle checkpoints use fixed, algorithm-specific challenges with immediate feedback. The opening unscored prediction also gives immediate feedback.
- Keep opponent answers private until the shared feedback gate opens. Neither public snapshots nor Realtime payloads may leak unreleased answers or rewards.
- Use previous, next, play, pause, and restart controls for replay. Show the frontier, current/expanded nodes, costs, and final route with labels and shapes as well as colour.
- Show the full search trace, including branches that do not become part of the walking route. Render a readable node/cost list as an alternative to the visual graph.
- Shared checkpoint scenarios must be identical for both players regardless of their earlier middle choice. Keep their source, goal, and trace snapshot fixed in the content definition.

## Scoring and competition

| Action | Points |
| --- | ---: |
| Correct checkpoint one answer | 20 |
| Correct standard middle answer | 20 |
| Correct bonus middle answer | 40 instead of 20 |
| Correct checkpoint three answer | 20 |
| Visit all three chosen checkpoints and reach the finish | 20 |
| Maximum, standard / bonus | 80 / 100 |
| Opening prediction, final understanding check, walking speed | 0 |

Highest score wins; equal scores are a draw. Show checkpoint progress and remaining available points. Shared rewards awaiting the other submission remain pending rather than revealing correctness through a score change. Final results must agree on both devices.

## Course and location

Prepare a candidate route through Lilybank Gardens, Lilybank House/Hetherington alternatives, and the Fraser Building between JMS and the Library. These landmarks are a survey proposal, not a verified accessible route. Use the [official campus map](https://www.gla.ac.uk/explore/maps/) and an outdoor accessibility check to freeze stopping points, coordinates, pedestrian polylines, measured distances, and graph costs. Both branches must rejoin before checkpoint three.

Use only accessible pedestrian paths with safe stopping areas. Validate the 500–800 m total and 50–100 m bonus increment from actual polylines. If access restrictions prevent the proposed course, record the issue and agree a revision rather than presenting invented or unchecked geometry as safe.

Default arrival verification is an explicit arrival action within a configurable 25 m radius, using a fresh and sufficiently accurate GPS fix. Define the freshness/accuracy thresholds in the shared course contract and test their boundaries. Request location only when needed and use foreground updates. Permission denial or poor accuracy must explain the next action.

Provide a server-verified organiser override for demo arrivals, including the start and finish where necessary. Keep override credentials out of source control and the client, rate-limit verification, and record that an override was used. Do not ship an unrestricted client-side bypass. Retain the last confirmed route when disconnected; do not assume MapKit basemap tiles are available offline.

## Design and navigation

Create an editable Figma flow before screen implementation: Home, Lobby, opening prediction, Match Map, Route Choice, Challenge/Feedback, AR Replay, and Results/Understanding Check. Include loading, empty, error, pending-feedback, and reconnecting states.

Use Appllama research to study interaction and hierarchy rather than copying assets. Relevant flows inspected during planning include Outdooractive Navigation, OS Maps Map Browsing, AllTrails Activity, Gizmo Quiz, and Busuu Checkpoint. Complete any remaining screen-type research before drawing the affected screens. Preserve durable screen IDs in design notes; keep bulky captures outside the repository.

The visual system uses one deep green accent, one neutral family, a 4/8-point spacing rhythm, continuous corners, native typography, SF Symbols, and tabular numerals. Keep the map readable and the graph dominant during learning tasks. Native Liquid Glass is limited to appropriate controls on iOS 26+; earlier versions retain usable standard surfaces.

Use a `NavigationStack` and state-driven Home → Lobby → Match → Results transitions. Challenges are dismissible task modals, route choice is a sheet, and AR is full-screen with Close. Dismissal preserves draft answers; back navigation must not undo submissions or return to an obsolete lobby/match. Use native sharing for room codes. Keep motion purposeful and interruptible, with Reduce Motion support.

## Architecture and shared interfaces

Keep business rules independent of SwiftUI in `Packages/AlgorithmArenaCore`. The core package depends on Foundation rather than MapKit, ARKit, or Supabase. Use explicit dependency injection and SwiftUI observation for app state.

Establish the following contracts before parallel implementation:

- `AlgorithmKind`: Dijkstra or A*.
- `CourseGraph`: versioned nodes, coordinates, walkable edge polylines/costs, start/finish, and checkpoint alternatives.
- `SearchTrace`: deterministic expansion/relaxation steps, frontier ordering, costs, predecessor changes, and final route.
- `ChallengeDefinition`: selected algorithm, fixed graph scenario, action type, reward, and gated feedback content.
- `MatchCommand`: authenticated actions with an idempotency identifier.
- `MatchSnapshot`: revision, course version, algorithm, match phase, authorised player progress, and currently available feedback.
- `MatchService`: app-facing protocol with mock and live implementations using the same fixtures.

Put wire examples and cross-language fixtures in `contracts/`. The backend owns the authoritative scored challenge definitions; public course data and mock fixtures must not inadvertently publish unreleased match answers. Publish course metadata identically to both clients and reject incompatible course versions clearly.

### Deterministic search

Use non-negative integer metre costs derived from the walking polylines. Dijkstra prioritises tentative cost; A* prioritises `g + h`. Break equal-priority ties by fixed node-ID order, traverse neighbours in that order, and preserve the existing predecessor when an equal-cost alternative is found.

Derive integer per-goal A* heuristics from straight-line distance and verify non-negativity, `h(goal) = 0`, admissibility, and edge-wise consistency against the final graph. Keep the same validated values in Swift and server fixtures. Test optimal cost equality between the algorithms without requiring identical routes when several optimal paths exist.

The pure Swift engine produces the route and replay trace. Both 2D and AR views consume that trace. Server-side validation uses the same versioned content and deterministic fixtures; it must not trust client-supplied correctness or points.

## Supabase and match reliability

Create a separate London-region project in the DYHTG organisation. Use anonymous authentication with a persisted session, nickname, and room code. Pin client dependencies and commit their lockfiles. Store only client-safe project configuration in the app; privileged credentials stay server-side.

Implement authenticated commands for creating/joining a room, changing/confirming the algorithm, readiness/start, arrival, route choice, answer submission, finish, and departure. Store membership/progress, private submissions, and a reward ledger. Validate membership, expected match phase, arrival/route prerequisites, and feedback eligibility server-side.

Use atomic database transitions, uniqueness constraints, and idempotency identifiers to prevent duplicate rewards, overfilled rooms, and conflicting route choices. Enable RLS for exposed tables and restrict room reads to members. Keep private submissions and unreleased feedback out of public room updates.

Use Supabase Realtime as an invalidation signal for a fresh authorised snapshot, not as the only record of progress. Refetch after reconnect and foregrounding; ignore stale revisions. Persist the session, active match, and pending command identifier so uncertain submissions can be reconciled safely.

During disconnection, display reconnecting status, retain the last confirmed route, and pause new authoritative actions until synchronisation returns. Explicit departure and temporary loss of connectivity have different outcomes. Final standings are authoritative only when both players complete the course.

## AR

Add AR after the complete 2D match works. At a stopped checkpoint, use RealityKit/ARKit to anchor a small graph on a detected horizontal surface. Reuse the same trace, node values, and playback controls. AR feedback obeys the same shared-answer gate as 2D feedback.

Keep 2D replay available when camera permission is denied, hardware lacks support, a surface cannot be found, or tracking fails. Stop the camera session on dismissal/backgrounding. Precise outdoor alignment and continuous camera-based navigation are outside scope.

## Delivery and ownership

1. Establish shared contracts and the editable design in parallel.
2. Build deterministic algorithms/content and Supabase foundations while the iOS shell uses fixtures.
3. Complete the simulated learning/game loop and authoritative backend, then integrate live multiplayer.
4. Add and validate outdoor navigation, route choice, and checkpoint AR.
5. Run two-phone acceptance for both algorithms and evaluate learning.

`Munaikh` owns the Swift core package, course/challenge data, shared contracts, and Supabase implementation. `owaini0` owns the editable design, SwiftUI views, platform adapters, assets, and Xcode project configuration. Shared-contract changes require fixture updates and review by both. See the work breakdown document for assigned issues and native GitHub dependencies.

## Acceptance criteria

### Algorithms and learning

- [ ] Dijkstra and A* produce deterministic traces and optimal costs on the prepared graph, including ties, relaxation, zero-cost test edges, and unreachable-node cases.
- [ ] A* heuristic validity is tested; Swift and server fixtures agree.
- [ ] Practice, each checkpoint option, and the final transfer question have correct algorithm-specific answers and worked explanations.
- [ ] Replays explain frontier selection, cost changes, and search versus walking route, including incorrect submissions.
- [ ] Shared feedback and rewards remain unavailable until both submissions; middle feedback is immediate.
- [ ] A new graph question and reason choice capture first-attempt understanding separately from score.

### Two-player match and recovery

- [ ] Two iPhones join one room, confirm the same algorithm, verify the shared start, and start together.
- [ ] Algorithm changes clear readiness; a third player cannot join.
- [ ] Players choose different middle checkpoints and each visits exactly three checkpoints before finishing.
- [ ] Correct and incorrect submissions both allow progression; standard/bonus maxima are 80/100.
- [ ] Concurrent/retried commands do not duplicate submissions or points; unauthorised reads/actions fail.
- [ ] Brief disconnects, uncertain submissions, app relaunch, and foregrounding restore consistent progress.
- [ ] Both devices agree on winner/draw; the first finisher waits, and explicit departure produces an incomplete result.

### Native experience and outdoor demo

- [ ] Course distances, access, stopping areas, GPS thresholds, and organiser override are checked outdoors.
- [ ] Camera/location denial, poor GPS, missing AR surfaces, tracking loss, and connectivity loss have usable recovery paths.
- [ ] At least one checkpoint demonstrates AR, with equivalent gated 2D replay available.
- [ ] Light/dark appearance, safe areas, Dynamic Type, VoiceOver, 44-point targets, contrast, and Reduce Motion are verified.
- [ ] Build iOS Apps simulator checks include recorded end-to-end flows, frame-by-frame transition review, keyboard appearance, rapid taps, dismissals, and interrupted gestures.
- [ ] Physical-device checks cover release-build interaction performance and real GPS/AR behaviour; simulator success alone does not satisfy these checks.
- [ ] Run a complete two-iPhone match for each algorithm, including different branches, a wrong answer, a reconnect, replay, and final result agreement.
- [ ] During the demo, ask each player to explain the selected algorithm's next-node rule and relate it to their final understanding-check answer. Record observed learning rather than assuming completion proves it.

## References

- [Original hackathon brief](https://chatgpt.com/space/page_6ad375120c8481919f1a31da21edc758) (requires access; this repository document includes the agreed requirements and later decisions).
- [University of Glasgow maps and accessibility information](https://www.gla.ac.uk/explore/maps/).
- [Berkeley CS 188: informed search and A*](https://inst.eecs.berkeley.edu/~cs188/textbook/search/informed.html).
- [Apple MapKit for SwiftUI](https://developer.apple.com/documentation/mapkit/mapkit-for-swiftui).
- [Supabase anonymous authentication](https://supabase.com/docs/guides/auth/auth-anonymous) and [Realtime Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).
