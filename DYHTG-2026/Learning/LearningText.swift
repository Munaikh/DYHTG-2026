import AlgorithmArenaCore

extension ChallengeSlot {
    var title: String {
        switch self {
        case .practice: "Warm-up"
        case .first: "Checkpoint 1"
        case .standardMiddle: "Checkpoint 2"
        case .bonusMiddle: "Bonus Checkpoint"
        case .third: "Checkpoint 3"
        case .learningCheck: "Understanding Check"
        }
    }
}

extension ChallengeDefinition {
    var pointsText: String {
        maximumPoints == 0 ? "Not scored" : "\(maximumPoints) points"
    }

    func label(_ id: NodeID) -> String {
        scenario.nodes.first { $0.id == id }?.label ?? id.rawValue
    }

    func text(for answer: SubmittedAnswer) -> String {
        switch answer {
        case .node(let id):
            return label(id)
        case .cost(let value):
            return String(value)
        case .route(let optionID):
            guard case .selectRoute(let options) = action else { return optionID }
            return options.first { $0.id == optionID }?.text ?? optionID
        case .transfer(let id, let reasonID):
            guard case .transfer(_, let reasons) = action,
                let reason = reasons.first(where: { $0.id == reasonID })
            else { return label(id) }
            return "\(label(id)), because \(reason.text.prefix(1).lowercased() + reason.text.dropFirst())"
        }
    }
}

struct StepDescription {
    let scenario: GraphScenario
    let algorithm: AlgorithmKind

    func text(for step: SearchStep, previous: SearchState?, outcome: SearchOutcome) -> String {
        let label = { (id: NodeID) in scenario.nodes.first { $0.id == id }?.label ?? id.rawValue }
        switch step.event {
        case .initial:
            return "Start at \(label(scenario.source)) with g = 0. Every other node is still unknown."
        case .expand(let id):
            let cost = (previous ?? step.state).costs.first { $0.nodeID == id }
            let g = cost?.g ?? 0
            switch algorithm {
            case .dijkstra:
                return "Expand \(label(id)). It has the lowest g on the frontier: \(g)."
            case .aStar:
                let h = cost?.h ?? 0
                return "Expand \(label(id)). It has the lowest f on the frontier: \(g) + \(h) = \(g + h)."
            }
        case .relax(let from, let to, let previousCost, let candidate, let accepted):
            let base = step.state.costs.first { $0.nodeID == from }?.g ?? 0
            let sum = "\(base) + \(candidate - base) = \(candidate)"
            guard let old = previousCost else {
                return "Check \(label(from)) to \(label(to)): \(sum). \(label(to)) had no cost yet, so g(\(label(to))) becomes \(candidate)."
            }
            if accepted {
                return "Check \(label(from)) to \(label(to)): \(sum). That beats \(old), so g(\(label(to))) becomes \(candidate)."
            }
            return "Check \(label(from)) to \(label(to)): \(sum). That doesn't beat \(old), so \(label(to)) keeps its cost."
        case .reachedGoal(let id):
            guard case .route(let nodes, let cost) = outcome else { return "Reached \(label(id))." }
            return "Reached the goal \(label(id)). The route to walk is \(nodes.map(label).joined(separator: " to ")), costing \(cost)."
        case .unreachable:
            return "The frontier is empty, so the goal can't be reached."
        }
    }
}

extension FeedbackAvailability {
    var challengeID: ChallengeID {
        switch self {
        case .pending(let challengeID): challengeID
        case .released(let feedback): feedback.challengeID
        }
    }
}
