# Campus graph and deterministic search

Implemented for [issue #4](https://github.com/Munaikh/DYHTG-2026/issues/4).
Routing accepts any two selected points on the supplied campus walking network.
The network's junctions describe physical connectivity; selected start/goal nodes
are generated per request and are independent of game checkpoints.

## Map adapter handoff

```swift
import AlgorithmArenaCore

// Replace this desktop candidate with the same approved network/version on both phones.
let course = try GilmorehillCourse.candidate()
let network = CampusPathNetwork(course: course)
let router = try CampusRouter(network: network, expected: course.reference)

// Coordinates come from the user's two map selections, not checkpoint IDs.
let graph = try router.graph(
  from: Coordinate(latitude: 55.87370, longitude: -4.29350),
  to: Coordinate(latitude: 55.87340, longitude: -4.28875)
)
let result = try graph.search(algorithm: .aStar) // or .dijkstra
// result.route: optional WalkingRoute; nil means no directed route exists.
// result.trace: complete SearchTrace for 2D/AR replay.
// graph.source/goal: requested and snapped coordinates, distance to path, node/path IDs.
// graph.scenario: the dynamic nodes, edges and published integer h values.
```

Map point selection and rendering belong to the iOS track; no SwiftUI/Xcode files
change in this issue. `CampusPathNetwork` can be loaded directly from JSON and
does not require constructing a `CourseGraph`. Pass the course reference from the
authorised match snapshot as `expected` in live integration; comparing a document
against its own reference, as above, is only appropriate for candidate inspection.

Before enabling a live outdoor match, call `router.requireOutdoorReadiness()`.
It rejects both synthetic and awaiting-survey data. The candidate covers the
proposed course area, not a surveyed complete-campus network. Extend and survey
the supplied paths to support selections throughout campus; the routing API and
algorithms do not impose the candidate's fixed landmarks or extent.

The default snapping limit is 25 m and can be configured per request. A point
farther from available paths returns `pointOutsideNetwork` with the affected
endpoint, distance and limit so the map can ask for a closer walking point. Gaps
between requested and snapped coordinates are reported rather than fabricated as
walkable edges. Network errors, invalid coordinates and version mismatches also
throw recoverable errors. UI copy should explain the next action.

## Building the dynamic graph

1. Validate version, unique path IDs, finite coordinates, positive polyline length,
   and consistent coordinates for every declared junction.
2. Project each selection onto the nearest path segment using a local campus-scale
   projection. Compare actual spherical distances; equal distances prefer the
   stable path ID then segment index.
3. Reuse an endpoint junction when selected, otherwise insert a selection node.
   Split paths at both selections in path order, retaining intermediate geometry
   and original directionality. Two points on the same path use its intervening
   section; identical points produce a zero-cost route.
4. Set each split edge's integer cost to the ceiling of its spherical polyline
   length in metres (Earth radius 6,371,008.8 m). Rounding each new piece can add a
   metre relative to an unsplit edge; both algorithms use the same generated costs.
5. Derive per-goal h by flooring the straight-line distance and validate it against
   the generated graph. Publish these exact integers for server parity.

Paths connect only through explicit shared junction IDs. Intersecting polylines
do not imply connectivity, and intermediate shape vertices are not automatically
junctions. A network author/importer must split paths at real pedestrian
intersections, preserve bridges/steps/access restrictions, and freeze a new network
version whenever connectivity or geometry changes. No live maps provider or
complete-campus network download is implemented in this Foundation-only package.

## Search and replay

`SearchEngine.search(_:algorithm:)` also accepts any validated `GraphScenario`
directly for teaching or backend fixtures. Dijkstra orders the frontier by g;
A* uses g+h. Both order equal priorities and neighbours by ASCII node ID. Parallel
neighbour edges use ascending cost as a secondary order. Equal-cost alternatives
preserve the predecessor, including on zero-cost cycles.

Every event includes the full state immediately afterward: initial, expand,
each attempted relaxation, reached goal or unreachable. Costs are node-ID ordered;
frontier is priority ordered; settled nodes are expansion ordered. A node's
expansion event identifies the current node. Rejected updates retain the old g
and predecessor. Search ends when the goal is expanded, so remaining frontier
nodes stay visible and explored branches remain separate from the final route.

A* rejects negative values, a nonzero goal heuristic, overestimation, or an
edge-wise inconsistency (including reverse traversal of bidirectional edges).
Validation independently computes exact goal distances on reversed edges.
Dijkstra ignores h for selection. Integer values and arithmetic are restricted
to JavaScript's exact nonnegative integer range; overflow throws instead of trapping
or silently rounding. Disconnected goals return `unreachable`; source = goal
returns one node, no edges and zero cost.

The full-state replay intentionally favours clarity on small campus graphs:
it retains O((V+E)V) state values and sorts the frontier when recording steps.
Avoid calling this synchronously from an animation frame for a large imported
network; profile that integration before introducing concurrency or a larger-graph
search implementation.

`CourseNavigator` is the separate optional adapter for authored game courses. It
validates checkpoint order, both complete branches, geometry and distances. Use
`route(for:)` when game rules require visiting mandatory stops; a free shortest
path can skip them. `CampusRouter` does not impose those stops on map selections.

## Verification and fixtures

```sh
swift test --package-path Packages/AlgorithmArenaCore
python3 scripts/verify_search_fixtures.py
swift run --package-path Packages/AlgorithmArenaCore export-contract-fixtures contracts/v1
```

The original 70 mock contract fixtures remain byte-identical. Additive files
bring the total to 111: eight graph scenarios and sixteen traces, the candidate
course/network, all seven per-goal heuristic tables, authored branch routes,
course traces and two dynamic requests with split graphs/routes/traces.

Tests compare 6,400 searches across 128 generated directed graphs against an
independent Floyd–Warshall oracle, including zeros and disconnected goals. They
also compare the engine against the original independently authored learning
traces; explicitly cover differing routes with equal optimal costs; and verify
dynamic interior selections, same-path/reverse travel, identical points, one-way
paths, unconnected crossings, snapping boundaries, invalid inputs and versions.
The Python stdlib verifier reproduces all 22 new golden traces, validates
admissibility/consistency independently and reconstructs dynamic route polylines.
CI runs both checks. Field access and location validation remain outdoor/backend
acceptance work, as recorded in the survey document.
