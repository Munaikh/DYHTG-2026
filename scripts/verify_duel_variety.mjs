// Cross-check Swift-authored solutions with an independent public-only JS solver.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {predictDuel,runDuelGraph} from './duel_prediction.mjs';
let count=0;
for(const algorithm of ['bfs','dfs','dijkstra','aStar','greedy']){
  const bank=JSON.parse(readFileSync(new URL(`../content/duel/v2/server/${algorithm}.json`,import.meta.url)));
  for(const document of bank){
    assert.equal(predictDuel(algorithm,document.round),document.correctNodeID,document.id);
    const result=runDuelGraph(document.round.scenario,algorithm);
    assert.deepEqual(result.route,document.trace.outcome.route.nodeIDs,document.id);
    assert.equal(result.cost,document.trace.outcome.route.cost,document.id);
    count++;
  }
}
console.log(`Verified ${count} varied questions against independent JS search and route reconstruction.`);
