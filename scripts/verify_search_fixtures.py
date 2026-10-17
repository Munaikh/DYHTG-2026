#!/usr/bin/env python3
"""Independent stdlib reference for the Swift/server golden search contract."""

import heapq
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "contracts" / "v1"
MAXIMUM_COST = 9_007_199_254_740_991


def load(path):
    return json.loads(path.read_text())


def adjacency(scenario):
    result = {node["id"]: [] for node in scenario["nodes"]}
    for edge in scenario["edges"]:
        assert 0 <= edge["cost"] <= MAXIMUM_COST
        result[edge["from"]].append((edge["to"], edge["cost"]))
        if edge["bidirectional"] and edge["from"] != edge["to"]:
            result[edge["to"]].append((edge["from"], edge["cost"]))
    return {node: sorted(edges) for node, edges in result.items()}


def validate_heuristics(scenario):
    """Floyd-Warshall checks admissibility independently of either search."""
    graph = adjacency(scenario)
    ids = sorted(graph)
    h = {node["id"]: node["heuristic"] for node in scenario["nodes"]}
    assert all(type(value) is int and 0 <= value <= MAXIMUM_COST for value in h.values())
    assert h[scenario["goal"]] == 0
    distances = {(a, b): 0 if a == b else math.inf for a in ids for b in ids}
    for source, edges in graph.items():
        for target, cost in edges:
            distances[source, target] = min(distances[source, target], cost)
            assert h[source] <= cost + h[target], (source, target, "inconsistent h")
    for middle in ids:
        for source in ids:
            for target in ids:
                distances[source, target] = min(
                    distances[source, target], distances[source, middle] + distances[middle, target]
                )
    assert all(h[node] <= distances[node, scenario["goal"]] for node in ids)
    return distances[scenario["source"], scenario["goal"]]


def reference_trace(scenario, algorithm):
    graph = adjacency(scenario)
    h = {node["id"]: node["heuristic"] for node in scenario["nodes"]}
    source, goal = scenario["source"], scenario["goal"]
    costs, parents = {source: 0}, {}
    frontier, settled, closed, steps = {source}, [], set(), []
    queue = []

    def priority(node):
        value = costs[node] + (h[node] if algorithm == "aStar" else 0)
        assert value <= MAXIMUM_COST
        return value

    def record(event, **payload):
        values = []
        for node in sorted(graph):
            value = {"nodeID": node, "h": h[node]}
            if node in costs:
                value["g"] = costs[node]
            if node in parents:
                value["predecessor"] = parents[node]
            values.append(value)
        steps.append({
            "index": len(steps), "event": {event: payload},
            "state": {"frontier": sorted(frontier, key=lambda node: (priority(node), node)),
                      "settled": list(settled), "costs": values},
        })

    heapq.heappush(queue, (priority(source), source))
    record("initial")
    outcome = {"unreachable": {}}
    while queue:
        queued_priority, current = heapq.heappop(queue)
        if current in closed or queued_priority != priority(current):
            continue
        frontier.remove(current)
        closed.add(current)
        settled.append(current)
        record("expand", nodeID=current)
        if current == goal:
            route = [current]
            while route[-1] in parents:
                route.append(parents[route[-1]])
            outcome = {"route": {"nodeIDs": route[::-1], "cost": costs[current]}}
            record("reachedGoal", nodeID=current)
            break
        for target, edge_cost in graph[current]:
            candidate, previous = costs[current] + edge_cost, costs.get(target)
            assert candidate <= MAXIMUM_COST
            accepted = target not in closed and (previous is None or candidate < previous)
            if accepted:
                costs[target], parents[target] = candidate, current
                frontier.add(target)
                heapq.heappush(queue, (priority(target), target))
            payload = {"from": current, "to": target, "candidateCost": candidate, "accepted": accepted}
            if previous is not None:
                payload["previousCost"] = previous
            record("relax", **payload)
    else:
        record("unreachable")
    return {"scenarioID": scenario["id"], "algorithm": algorithm, "steps": steps, "outcome": outcome}


def check_trace(scenario, algorithm, path):
    optimal = validate_heuristics(scenario)
    expected = load(path)
    actual = reference_trace(scenario, algorithm)
    assert actual == expected, f"Trace parity failure: {path.relative_to(ROOT)}"
    if math.isinf(optimal):
        assert actual["outcome"] == {"unreachable": {}}
    else:
        assert actual["outcome"]["route"]["cost"] == optimal


def metres(a, b):
    lat_a, lat_b = math.radians(a["latitude"]), math.radians(b["latitude"])
    delta_lat = lat_b - lat_a
    delta_lon = math.radians(b["longitude"] - a["longitude"])
    value = math.sin(delta_lat / 2) ** 2 + math.cos(lat_a) * math.cos(lat_b) * math.sin(delta_lon / 2) ** 2
    return 2 * 6_371_008.8 * math.asin(math.sqrt(min(1, max(0, value))))


def check_geometry(edges):
    for edge in edges:
        points = edge["polyline"]
        length = sum(metres(a, b) for a, b in zip(points, points[1:]))
        assert edge["costMetres"] == math.ceil(length), edge["id"]


def check_walking_route(graph, route, trace):
    assert route["course"] == graph["network"]
    assert route["nodeIDs"] == trace["outcome"]["route"]["nodeIDs"]
    assert route["distanceMetres"] == trace["outcome"]["route"]["cost"]
    by_id = {edge["id"]: edge for edge in graph["edges"]}
    points = [graph["source"]["coordinate"]]
    total = 0
    assert len(route["edgeIDs"]) == len(route["nodeIDs"]) - 1
    for index, edge_id in enumerate(route["edgeIDs"]):
        edge = by_id[edge_id]
        a, b = route["nodeIDs"][index:index + 2]
        if (a, b) == (edge["from"], edge["to"]):
            polyline = edge["polyline"]
        else:
            assert edge["bidirectional"] and (b, a) == (edge["from"], edge["to"])
            polyline = edge["polyline"][::-1]
        assert points[-1] == polyline[0]
        points.extend(polyline[1:])
        total += edge["costMetres"]
    assert points == route["polyline"] and total == route["distanceMetres"]
    assert points[-1] == graph["goal"]["coordinate"]


def main():
    count = 0
    for path in sorted((ROOT / "search").glob("*/scenario.json")):
        scenario = load(path)
        for algorithm in ("dijkstra", "aStar"):
            check_trace(scenario, algorithm, path.with_name(f"{algorithm}.json"))
            count += 1
    assert count >= 16, "Missing synthetic search fixtures"
    for course_path in sorted((ROOT / "courses").glob("*/*/course.json")):
        course = load(course_path)
        check_geometry(course["edges"])
        tables = load(course_path.with_name("heuristics.json"))
        assert {table["goal"] for table in tables} == {node["id"] for node in course["nodes"]}
        for table in tables:
            assert table["course"] == course["reference"]
            h = {value["nodeID"]: value["h"] for value in table["values"]}
            scenario = {
                "nodes": [{"id": node["id"], "heuristic": h[node["id"]]} for node in course["nodes"]],
                "edges": [{"from": edge["from"], "to": edge["to"], "cost": edge["costMetres"], "bidirectional": edge["bidirectional"]} for edge in course["edges"]],
                "source": course["stops"]["start"], "goal": table["goal"],
            }
            validate_heuristics(scenario)
            for node in course["nodes"]:
                target = next(n for n in course["nodes"] if n["id"] == table["goal"])
                assert h[node["id"]] == math.floor(metres(node["coordinate"], target["coordinate"]))
            if table["goal"] == course["stops"]["finish"]:
                for algorithm in ("dijkstra", "aStar"):
                    version = json.loads(json.dumps(scenario))
                    components = [course["reference"]["id"], course["reference"]["version"], version["source"], version["goal"]]
                    version["id"] = ":".join(f"{len(part.encode('utf-8'))}:{part}" for part in components)
                    if algorithm == "dijkstra":
                        for node in version["nodes"]:
                            node["heuristic"] = 0
                    check_trace(version, algorithm, course_path.with_name(f"{algorithm}-trace.json"))
                    count += 1
        for graph_path in sorted(course_path.parent.glob("requests/*/graph.json")):
            graph = load(graph_path)
            assert graph["network"] == course["reference"]
            check_geometry(graph["edges"])
            for endpoint in ("source", "goal"):
                point = graph[endpoint]
                assert math.isclose(metres(point["requested"], point["coordinate"]), point["distanceToPathMetres"], abs_tol=1e-6)
            for algorithm in ("dijkstra", "aStar"):
                trace_path = graph_path.with_name(f"{algorithm}-trace.json")
                check_trace(graph["scenario"], algorithm, trace_path)
                check_walking_route(graph, load(graph_path.with_name(f"{algorithm}-route.json")), load(trace_path))
                count += 1
    print(f"Verified {count} Swift/Python golden traces, per-goal heuristics and dynamic route geometry.")


if __name__ == "__main__":
    main()
