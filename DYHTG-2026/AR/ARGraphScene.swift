import AlgorithmArenaCore
import RealityKit
import UIKit

@MainActor
final class ARGraphScene {
    private struct NodeEntities {
        let sphere: ModelEntity
        let label: ModelEntity
        let cost: ModelEntity
    }

    private let width: Float = 0.36
    private let rowSpacing: Float = 0.12
    private let nodeRadius: Float = 0.016
    private var nodes: [NodeID: NodeEntities] = [:]
    private var edges: [(edge: ScenarioEdge, entity: ModelEntity)] = []
    private var costs: [NodeID: String] = [:]

    func build(_ presentation: SearchPresentation, on anchor: AnchorEntity) {
        let layout = GraphLayout(scenario: presentation.scenario)
        let depth = Float(max(layout.rows - 1, 1)) * rowSpacing
        let root = Entity()
        anchor.addChild(root)

        let plate = ModelEntity(
            mesh: .generateBox(width: width + 0.08, height: 0.002, depth: depth + 0.14, cornerRadius: 0.01),
            materials: [UnlitMaterial(color: UIColor.white.withAlphaComponent(0.55))]
        )
        root.addChild(plate)

        func position(_ id: NodeID) -> SIMD3<Float> {
            let unit = layout.positions[id] ?? .zero
            return [Float(unit.x - 0.5) * width, 0.02, Float(unit.y - 0.5) * depth]
        }

        for edge in presentation.scenario.edges {
            let from = position(edge.from)
            let to = position(edge.to)
            let entity = ModelEntity(mesh: .generateBox(width: simd_distance(from, to), height: 0.003, depth: 0.003))
            entity.position = (from + to) / 2
            entity.orientation = simd_quatf(angle: atan2(-(to.z - from.z), to.x - from.x), axis: [0, 1, 0])
            root.addChild(entity)
            edges.append((edge, entity))

            let cost = text(String(edge.cost), size: 0.014, color: .darkGray)
            cost.position = (from + to) / 2 + [0, 0.01, 0]
            root.addChild(cost)
        }

        for node in presentation.nodes {
            let sphere = ModelEntity(mesh: .generateSphere(radius: nodeRadius))
            sphere.position = position(node.id)
            let label = text(node.label, size: 0.02, color: .black)
            label.position = sphere.position + [0, 0.026, 0]
            let cost = text("", size: 0.012, color: .darkGray)
            cost.position = sphere.position + [0, -0.004, 0.03]
            root.addChild(sphere)
            root.addChild(label)
            root.addChild(cost)
            nodes[node.id] = NodeEntities(sphere: sphere, label: label, cost: cost)
        }

        update(presentation, highlightedEdge: nil)
    }

    func update(_ presentation: SearchPresentation, highlightedEdge: (from: NodeID, to: NodeID)?) {
        let accent = UIColor(named: "AccentColor") ?? .systemBlue
        for node in presentation.nodes {
            guard let entities = nodes[node.id] else { continue }
            let (color, scale): (UIColor, Float) = switch node.state {
            case .undiscovered: (.white, 0.8)
            case .frontier: (accent.withAlphaComponent(0.55), 1)
            case .current: (accent, 1.4)
            case .settled: (.systemGray, 0.9)
            case .route: (accent, 1.15)
            }
            entities.sphere.model?.materials = [SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)]
            entities.sphere.scale = [scale, scale, scale]

            let caption = presentation.costText(node)
            if costs[node.id] != caption {
                costs[node.id] = caption
                entities.cost.model?.mesh = Self.mesh(for: caption, size: 0.012)
            }
        }

        let route = presentation.routeEdges
        for (edge, entity) in edges {
            let key = "\(edge.from.rawValue)>\(edge.to.rawValue)"
            let reverse = "\(edge.to.rawValue)>\(edge.from.rawValue)"
            let onRoute = route.contains(key) || (edge.bidirectional && route.contains(reverse))
            let active = highlightedEdge.map { $0.from == edge.from && $0.to == edge.to } ?? false
            let color: UIColor = onRoute || active ? accent : .gray
            entity.model?.materials = [UnlitMaterial(color: color)]
            entity.scale = onRoute ? [1, 2.5, 2.5] : [1, 1, 1]
        }
    }

    private func text(_ string: String, size: CGFloat, color: UIColor) -> ModelEntity {
        ModelEntity(mesh: Self.mesh(for: string, size: size), materials: [UnlitMaterial(color: color)])
    }

    private static func mesh(for string: String, size: CGFloat) -> MeshResource {
        MeshResource.generateText(
            string,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: size, weight: .semibold),
            containerFrame: CGRect(x: -0.06, y: -size, width: 0.12, height: size * 2),
            alignment: .center,
            lineBreakMode: .byClipping
        )
    }
}
