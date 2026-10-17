# Gilmorehill network / course survey candidate

Reference: `gilmorehill-jms-library`, version `candidate-2026-10-17-1`.
Readiness: **awaitingSurvey**. Prepared on 17 October 2026 for issue #4.

The candidate follows the agreed JMS → Lilybank Gardens → Lilybank House or
Hetherington → common Bute Gardens rejoin → Fraser Building → Library proposal.
The routing engine accepts arbitrary selected points on these paths and any
additional campus paths supplied later. The game checkpoints are sample course
configuration, not fixed search endpoints.

## Sources and evidence status

- [University maps page](https://www.gla.ac.uk/explore/maps/), checked 17 October 2026.
- [Official campus map, updated March 2026](https://www.gla.ac.uk/media/Media_1167819_smxx.pdf),
  checked 17 October 2026. It identifies the proposed landmarks and cautions that
  redevelopment may restrict routes.
- [Agreed proposal](PLAN.md#course-and-location).

These sources establish the landmark proposal, not measured pedestrian geometry.
**Every coordinate, path vertex and stopping area in this candidate is a manually
estimated desktop sketch.** No access permission, step-free connection, entrance,
road crossing or safe stopping space has been verified. Polylines are proposed
links to inspect, not asserted public footpaths. No outdoor survey took place.
The dataset is intentionally blocked by `requireOutdoorReadiness()`.

## Provisional geometry arithmetic

Costs are ceilings of summed spherical segment lengths, not manually chosen
distance targets. These are lengths of the sketch only:

| Proposed link | Integer metres |
| --- | ---: |
| JMS → Lilybank Gardens | 146 |
| Lilybank Gardens → Lilybank House | 118 |
| Lilybank House → rejoin | 151 |
| Lilybank Gardens → Hetherington alternative | 313 |
| Hetherington → rejoin | 48 |
| Rejoin → Fraser | 88 |
| Fraser → Library | 104 |
| Standard total | 607 |
| Bonus total | 699 |
| Bonus increment | 92 |

Both proposed branches rejoin before checkpoint three. Sketch totals meet the
500–800 m and 50–100 m increment targets; actual field measurements may not.
Seven exact integer heuristic tables, one per node as goal, accompany this
version. All are checked for non-negativity, h(goal)=0, admissibility and
consistency. Dynamic selection graphs validate freshly derived h after splitting.

## Outdoor freeze handoff

Munaikh and owaini0 should inspect each proposed link and alternative, replace
estimated vertices with recorded pedestrian geometry, and confirm junction
connectivity rather than inferring it from intersecting lines. Record restrictions,
steps, ramps, gates/opening hours, construction, road crossings, stopping space
and an accessible alternative where required. Expand the network beyond this
candidate area before offering selections across the entire campus.

Measure both complete branches again and confirm three stops each, the common
rejoin, target distances and bonus increment. If access invalidates the proposal,
record the failed link and agree revised geometry. Reassess 25 m arrival radius,
10 s fix age and 20 m horizontal accuracy outdoors; authoritative GPS validation
and organiser override verification remain with backend/location integration.

Freeze the approved data under a **new immutable version**, regenerate all costs,
per-goal h tables and fixtures, rerun Swift/Python checks, and record the survey
date/evidence here before setting readiness to `surveyed`. Both devices and the
server must use exactly that approved reference and data; reject mismatched
versions rather than reusing cached geometry silently.
