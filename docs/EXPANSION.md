> Historical experiment: the active app uses Learn, Plot Twist Duel, and the
> educational campus Visualize tab described in [README](../README.md).
> The welcome tour and local profile editor have been integrated into that shell.
> The friend-battle, email-account, and real-road features below remain dormant;
> their migration and deployment steps are not required for the active app.

# Friend battles and Pathfinder

The original campus game, its contracts, QR/organiser arrivals, solo practice,
AR and results remain intact. New destinations use the existing SwiftUI
Form/List, typography, colours and PrimaryButton. No new app dependencies.

## What is implemented

- Three animated first-launch screens. Completion is local to the installation.
  More → Settings → Replay Onboarding opens them again. Reduce Motion is respected.
- Private two-player battles using the existing Supabase project and SDK.
  Share a room code, join, ready up, then race to 100. Realtime sends only room ID
  and revision; member-only RPCs fetch state. Five-second polling recovers missed
  events and updates presence. Revisions prevent stale snapshots replacing newer state.
- The same server-created round is used by both players. BFS paths, DFS visitation,
  weighted Dijkstra/A* paths, sorting and binary-search traces are interactive.
  Graphs/weights and array sizes increase. Multiple equally optimal paths are accepted.
  Answers stay server-private; the server checks paths, visits, ordering and search steps.
  Correct rounds earn `min(24, 10 + 2*round)` progress, with 3 extra for a correct
  first attempt within 20 seconds. No points for incorrect answers. Each player's
  submitted round is checked under the shared room lock, preventing duplicate scoring.
- At 100, the server finishes the room and writes two results with a unique
  `(battle,player)` key in the same transaction. Profiles derive real wins, losses,
  streaks, rates and recent history from those results. Abandoned matches do not count.
- Email OTP accounts restore battle identity across devices. Original campus
  anonymous sign-in remains available. A name or room code is not an account recovery key.
- After 20 seconds without the opponent's heartbeat, scoring pauses. A player
  returning within five minutes resumes; after five minutes the room is abandoned
  without an artificial win. Closing/leaving never fabricates results. Rematches
  create one shared new room and reset both players' scores/readiness.
- Apple Maps searches addresses and POIs. Pathfinder downloads real OSM nodes and
  road segments, builds an adjacency graph, and runs Dijkstra, A* or BFS locally.
  Playback supports start, pause, reset and speed. Comparison uses actual visited
  counts, graph-edge counts and route distance, not provider summary estimates.
- Friend routes require a room, request, acceptance, and a separate Share My Position
  action from each participant. Joining a room never accesses or exposes location.
  Positions are one-shot samples, not live tracking. Either party can decline/stop.

## Setup before hosted use

The new backend is supplied as a migration; it has **not been deployed by this change**.
The existing app points at the existing Supabase project via `Live/ArenaBackend.swift`.
Its publishable key is client-safe. Never embed a service-role key or SMTP credential.
For another environment, replace URL/publishable key in that configuration (or generate
it from your build environment); keep server credentials only in Supabase.

1. Apply all migrations to a local/test project first, then review and deploy
   `supabase/migrations/20261017203000_friend_battles.sql` to the intended project.
   Existing migrations must precede it. The new tables are private with RLS; only
   `public.battle_invalidations` replicates, with member-only SELECT.
2. Enable the Supabase **Email** auth provider and email signup. The local config
   now enables email signup. Configure production SMTP in the dashboard.
3. Change the **Magic Link email template** to display `{{ .Token }}` as the
   sign-in code. The app verifies the code using `.email`; it does not need an
   email deep-link handler. Follow [Supabase OTP documentation](https://supabase.com/docs/guides/auth/auth-email-passwordless#with-otp).
4. As database owner, run `supabase/enable_location_expiry.sql`. It enables pg_cron,
   schedules expiry deletion every minute, then enables the sharing capability.
   Sharing requests fail closed until this succeeds. Confirm the
   `friend-location-expiry` job appears in `cron.job` and monitor `cron.job_run_details`.
   Supabase's scheduler must remain enabled. Expired positions become unreadable
   immediately; physical deletion is within a minute. Stop/decline and completion
   delete immediately. No location history or request-body logging is implemented.
5. Build in Xcode and sign in with two different email accounts on two devices.
   Save profiles, create/join a room, confirm real-time readiness and scoring, finish
   a battle, then sign into one account on another device and verify the same history.
   Use a test project and test accounts for this acceptance check.

The app shows actual service errors rather than simulating a connected opponent,
successful email, a road route or statistics when setup is incomplete.

## Routing assumptions and scope

Distances are the sum of geodesic lengths of consecutive real OSM way nodes.
Dijkstra has non-negative weights. A* uses geodesic distance to the goal; the
triangle inequality makes that a lower bound for these segment weights. BFS
uses one per segment and minimises **edges**, which can yield a longer distance.
All three results are computed on the same downloaded graph. No fastest-time
objective is claimed. Walking estimates use 1.4 m/s, with no live traffic,
terrain, crossing delay or opening-hour model.

Queries cover endpoints at most 3 km apart with roughly 500 m margins. Overpass
is preferred; the official OSM map API is a fallback. Nodes/ways tagged private,
no-foot-access, area-only pedestrian polygons and blocked barriers are excluded.
`oneway:foot` is respected; motor-vehicle one-way tags are not imposed on walking.
Conditional access restrictions, relation-based turn restrictions and wheelchair
access are not modelled. Endpoints must snap within 150 m of a road node; any
remaining off-road distance is excluded. Optimality applies to the fetched graph,
not the entire world's road network. The map marks the selected locations while
highlighting only actual road segments. Provider timeout/limits and disconnected
networks have explicit errors. No straight-line fallback is presented as a route.

For high-traffic production use, host/cache a read-only OSM extract service rather
than relying on community public endpoints. Precise friend positions are sent to
the routing provider only when the user chooses to calculate a friend route.
The optional Meet Halfway bonus is not included.

## Verification

```sh
swift test --package-path Packages/AlgorithmArenaCore
python3 scripts/verify_search_fixtures.py
python3 -B scripts/verify_learning_content.py
xcodebuild -project DYHTG-2026.xcodeproj -scheme DYHTG-2026 \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Isolated PostgreSQL runtime, no hosted users or data touched:
npm install --prefix /tmp/arena-db --no-save @electric-sql/pglite@0.3.14
PGLITE_MODULE=/tmp/arena-db/node_modules/@electric-sql/pglite/dist/index.js \
  node scripts/test_friend_battles.mjs
```

The isolated database test checks auth, two-seat capacity, membership/RLS,
private answers, equivalent rounds, scoring, duplicate/stale submissions,
exactly-once results, streaks, rematch reuse, disconnection and consent/expiry.
It does not replace testing hosted Auth email delivery, Realtime transport,
concurrent requests through PostgREST or GPS on physical devices. Run the
existing Supabase integration scripts too when the local Supabase stack is available.
