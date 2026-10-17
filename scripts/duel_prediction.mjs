// Independent test-player solver. Reads ONLY public graphs/states, never the answer bank.
export function runDuelGraph(scenario,algorithm) {
  const frontier=[scenario.source],visited=[],costs=new Map([[scenario.source,0]]),parents=new Map();
  const heuristic=new Map(scenario.nodes.map(n=>[n.id,n.heuristic]));
  const adjacency=new Map();
  for(const edge of scenario.edges){
    if(!adjacency.has(edge.from))adjacency.set(edge.from,[]);
    adjacency.get(edge.from).push({to:edge.to,cost:edge.cost});
    if(edge.bidirectional&&edge.from!==edge.to){
      if(!adjacency.has(edge.to))adjacency.set(edge.to,[]);
      adjacency.get(edge.to).push({to:edge.from,cost:edge.cost});
    }
  }
  const compareID=(a,b)=>a<b?-1:a>b?1:0;
  for(const arcs of adjacency.values())arcs.sort((a,b)=>compareID(a.to,b.to)||a.cost-b.cost);
  const weighted=algorithm==='dijkstra'||algorithm==='aStar';
  const priority=id=>algorithm==='greedy'?heuristic.get(id):costs.get(id)+(algorithm==='aStar'?heuristic.get(id):0);
  while(frontier.length){
    if(weighted||algorithm==='greedy')frontier.sort((a,b)=>priority(a)-priority(b)||compareID(a,b));
    const current=frontier.shift();visited.push(current);
    if(current===scenario.goal){
      const route=[current];while(parents.has(route[0]))route.unshift(parents.get(route[0]));
      return {route,visited,cost:costs.get(current)};
    }
    const arcs=adjacency.get(current)||[];
    for(const arc of algorithm==='dfs'?[...arcs].reverse():arcs){
      const candidate=costs.get(current)+arc.cost;
      const accepted=weighted ? !visited.includes(arc.to)&&(!costs.has(arc.to)||candidate<costs.get(arc.to)) :
        algorithm==='dfs' ? !visited.includes(arc.to) : !costs.has(arc.to);
      if(!accepted)continue;
      costs.set(arc.to,candidate);parents.set(arc.to,current);
      if(algorithm==='dfs'){
        const old=frontier.indexOf(arc.to);if(old>=0)frontier.splice(old,1);frontier.unshift(arc.to);
      }else if(!frontier.includes(arc.to))frontier.push(arc.to);
    }
  }
  throw Error('No route in the public graph');
}
export function predictDuel(algorithm,round){
  const result=runDuelGraph(round.scenario,algorithm);
  let answer;
  switch(round.questionKind||'nextExpansion'){
    case 'predecessor':answer=round.presentedState.costs.find(c=>c.nodeID===round.focusNodeID)?.predecessor;break;
    case 'routeHop':answer=result.route[1];break;
    case 'goalPredecessor':answer=result.route.at(-2);break;
    case 'nextExpansion':answer=result.visited[round.presentedState.settled.length];break;
    default:throw Error('Unsupported public question type');
  }
  if(!round.choices.includes(answer))throw Error('Prediction is not one of the public choices');
  return answer;
}
