import AlgorithmArenaCore
import Foundation

struct ChallengeDraft: Equatable {
    var node: NodeID?
    var cost = ""
    var routeOptionID: String?
    var reasonID: String?

    func answer(for action: ChallengeAction) -> SubmittedAnswer? {
        switch action {
        case .selectNode:
            return node.map { .node(nodeID: $0) }
        case .enterCost:
            return Int(cost.trimmingCharacters(in: .whitespaces)).map { .cost(value: $0) }
        case .selectRoute:
            return routeOptionID.map { .route(optionID: $0) }
        case .transfer:
            guard let node, let reasonID else { return nil }
            return .transfer(nodeID: node, reasonID: reasonID)
        }
    }
}
