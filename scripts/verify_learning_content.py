#!/usr/bin/env python3
"""Independent arithmetic, answer, privacy and full replay audit of the #5 bank."""

import json
import re
from pathlib import Path

from verify_search_fixtures import reference_trace, validate_heuristics


ROOT = Path(__file__).resolve().parents[1] / "content" / "learning" / "v1"
SLOTS = {"practice", "first", "standardMiddle", "bonusMiddle", "third", "learningCheck"}


def keys(value):
    if isinstance(value, dict):
        return set(value).union(*(keys(child) for child in value.values()))
    if isinstance(value, list):
        return set().union(*(keys(child) for child in value))
    return set()


def route_cost(graph, nodes):
    return sum(next(edge["cost"] for edge in graph["edges"]
                    if edge["from"] == a and edge["to"] == b)
               for a, b in zip(nodes, nodes[1:]))


def check(path):
    content = json.loads(path.read_text())
    definition = content["definition"]
    graph, algorithm = definition["scenario"], definition["algorithm"]
    slot = definition["slot"]
    prompt_path = ROOT / "prompts" / algorithm / f"{slot}.json"
    assert json.loads(prompt_path.read_text()) == definition
    assert keys(definition).isdisjoint({
        "correctAnswer", "isCorrect", "explanation", "workedSteps", "trace",
        "answers", "awardedPoints", "workedStepTraceIndices", "presentedStepIndex", "routes",
    })
    assert graph["id"].startswith(f"learning-{algorithm}-{slot}-")
    optimal = validate_heuristics(graph)
    trace = content["trace"]
    assert trace == reference_trace(graph, algorithm), path
    assert trace["outcome"]["route"]["cost"] == optimal
    index = content["presentedStepIndex"]
    state = definition["presentedState"]
    assert state == trace["steps"][index]["state"]
    assert definition["feedbackGate"] == (
        "afterBothSubmissions" if slot in {"first", "third"} else "immediate")
    assert definition["maximumPoints"] == (
        0 if slot in {"practice", "learningCheck"} else 40 if slot == "bonusMiddle" else 20)
    action, answer = definition["action"], content["correctAnswer"]
    costs = {cost["nodeID"]: cost for cost in state["costs"]}
    if "node" in answer or "transfer" in answer:
        ordered = sorted(state["frontier"], key=lambda node: (
            costs[node]["g"] + (costs[node]["h"] if algorithm == "aStar" else 0), node))
        selected = answer.get("node", answer.get("transfer"))["nodeID"]
        assert selected == ordered[0]
        assert trace["steps"][index + 1]["event"] == {"expand": {"nodeID": selected}}
        if "transfer" in answer:
            assert answer["transfer"]["reasonID"] == "frontier-priority"
            assert "frontier-priority" in {reason["id"] for reason in action["transfer"]["reasons"]}
    elif "cost" in answer:
        target = action["enterCost"]["nodeID"]
        current = state["settled"][-1]
        if slot == "bonusMiddle":
            update = next(step["event"]["relax"] for step in trace["steps"][index + 1:]
                          if "relax" in step["event"] and step["event"]["relax"]["to"] == target
                          and step["event"]["relax"]["accepted"])
            intermediate = update["from"]
            candidate = costs[current]["g"] + route_cost(graph, [current, intermediate, target])
            first_update = costs[current]["g"] + route_cost(graph, [current, intermediate])
            assert first_update < costs[intermediate]["g"]
        else:
            candidate = costs[current]["g"] + route_cost(graph, [current, target])
            update = trace["steps"][index + 1]["event"]["relax"]
        assert answer["cost"]["value"] == min(costs[target]["g"], candidate)
        assert update["candidateCost"] == candidate and update["accepted"]
        assert update["previousCost"] == costs[target]["g"]
    elif "route" in answer:
        totals = {option: route_cost(graph, nodes) for option, nodes in content["routes"].items()}
        selected = answer["route"]["optionID"]
        assert totals[selected] == min(totals.values()) == optimal
        assert content["routes"][selected] == trace["outcome"]["route"]["nodeIDs"]
    else:
        raise AssertionError(f"Unknown answer: {answer}")
    assert len(content["workedSteps"]) == len(content["workedStepTraceIndices"]) > 0
    for text, indices in zip(content["workedSteps"], content["workedStepTraceIndices"]):
        assert indices and all(0 <= ref < len(trace["steps"]) for ref in indices)
        for terms, result in re.findall(r"(\d+(?: \+ \d+)+) = (\d+)", text):
            assert sum(map(int, terms.split(" + "))) == int(result), text
        for a, b in re.findall(r"(\d+) < (\d+)", text):
            assert int(a) < int(b), text
    for node in graph["nodes"]:
        assert all(0 <= value <= 1 for value in node["position"].values())
    return algorithm, slot, graph["id"]


def main():
    found = [check(path) for path in sorted((ROOT / "server").glob("*/*.json"))]
    assert len(found) == 12
    assert len({scenario for _, _, scenario in found}) == 12
    for algorithm in ("dijkstra", "aStar"):
        assert {slot for kind, slot, _ in found if kind == algorithm} == SLOTS
    assert len(list((ROOT / "prompts").glob("*/*.json"))) == 12
    print("Verified 12 authored challenges: independent answers, arithmetic, prompt privacy and Swift/Python replay parity.")


if __name__ == "__main__":
    main()
