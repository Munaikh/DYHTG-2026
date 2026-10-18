# Lessons and questions review — 18 October 2026

Reviewed the repository content at `ac25276`, after fetching origin. The latest
`origin/main` commit was `bf4ab26`; its lesson, question, and authoring-script
content matches this checkout. Existing Xcode project and package-resolution
edits were preserved.

## Coverage and results

| Content | Instances | Validation |
| --- | ---: | --- |
| Five-algorithm study lessons and practice | 30 | All five algorithms, both modes, all three activities; independent recursive DFS, layer-based BFS, priority calculations, route costs and heuristic validation |
| Public Dijkstra and A* guided lessons | 6 | Authored arithmetic, choices, before/reveal states, transfer graphs and search traces |
| Match learning challenges | 12 | Independent Python answers, arithmetic, full traces, heuristic constraints, worked-step references and public/private document parity |
| Current duel bank (v2) | 120 | Independent JavaScript answers/routes and Swift full-trace, state, choice, heuristic and graph-twist checks |
| Legacy duel bank (v1) | 6 | Independent Python traces, heuristics, next-expansion answers and answer membership, plus existing Swift contract tests |
| **Total** | **174** | **No incorrect answer keys found** |

Read the authored rules, caveats, question generators, explanations and replay
copy alongside the computational checks. Generated instances share these
reviewed templates. The lesson examples correctly distinguish search expansion
from the final route, g from f, discovery from expansion, and BFS/DFS/Greedy from
weighted shortest-path algorithms.

## Corrections made

- Changed the shared BFS rule from “nearby points” to number of edges from the
  start, avoiding a visual-distance interpretation.
- Displayed the existing algorithm-specific ordering/tie rule before study
  answers. Equal priorities otherwise leave learners without enough information
  to choose the single accepted answer.
- Reworded the public A* question to ask which node comes next, matching its node
  answer options rather than asking a yes/no question.
- Added `StudyContentAuditTests.swift` to check every study activity independently
  of the trace event used to generate its stored answer.

The BFS/DFS distinctions were checked against [Princeton's graph-search
material](https://algs4.cs.princeton.edu/41graph/index.php). A* heuristic
assumptions were checked against [Berkeley CS188 search
notes](https://inst.eecs.berkeley.edu/~cs188/fa22/assets/notes/cs188-fa22-note02.pdf).

## Validation

- `swift test --disable-sandbox --package-path Packages/AlgorithmArenaCore`
  with writable module caches: **99 tests passed**, including the new audit's
  ten algorithm/mode cases covering all 30 study activities.
- `python3 -B scripts/verify_learning_content.py`: **12 challenges passed**.
- `node scripts/verify_duel_variety.mjs`: **120 questions passed**.
- Additional Python reference-trace audit: **6 legacy questions passed**.
- `git diff --check`: passed.

Scope: repository source and committed banks. The hosted database was not read
or changed; this review does not establish that its deployed content matches
these files. No simulator/device UI validation or full app build was performed.
