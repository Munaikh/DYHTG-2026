import AlgorithmArenaCore
import Foundation
import MapKit
import Observation

/// The only network adapter for the map lab. Successful geometry is cached for
/// this session; a failed Apple request never falls back to a straight line.
@MainActor @Observable
final class CampusRouteLoader {
    private(set) var experiment: CampusLabExperiment?
    private(set) var isLoading = false
    private(set) var status = "Choose a journey"
    private(set) var errorMessage: String?

    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cache: [String: [Coordinate]] = [:]
    @ObservationIgnored private let provider: (Coordinate, Coordinate) async throws -> [Coordinate]
    @ObservationIgnored private let cancelProvider: () -> Void

    init() {
        let directions = CampusWalkingDirections()
        provider = { try await directions.route(from: $0, to: $1) }
        cancelProvider = { directions.cancel() }
    }

    /// Injection exercises the production lifecycle without hitting Apple's service.
    init(provider: @escaping (Coordinate, Coordinate) async throws -> [Coordinate], cancel: @escaping () -> Void = {}) {
        self.provider = provider
        cancelProvider = cancel
    }

    func cancel() {
        generation = UUID()
        cancelProvider()
        isLoading = false
    }

    func load(from selectedSource: CampusMapPoint, to selectedGoal: CampusMapPoint, closedPathID: EdgeID? = nil) async {
        cancel()
        let token = generation
        experiment = nil
        errorMessage = nil
        isLoading = true
        status = "Connecting campus paths…"
        defer { if generation == token { isLoading = false } }
        do {
            guard CampusMapPoint.contains(selectedSource.coordinate), CampusMapPoint.contains(selectedGoal.coordinate) else {
                throw LoadError.outsideCampus
            }
            guard try CourseGeometry.distance(from: selectedSource.coordinate, to: selectedGoal.coordinate) >= 6 else {
                throw LoadError.samePoint
            }
            // A live Apple place result can refine a known landmark. Use that
            // location for directions too, instead of duplicating the place.
            let landmarks = CampusMapPoint.landmarks.prefix(7).map { landmark in
                if selectedSource.isAppleMapsPlace && selectedSource.id == landmark.id { return selectedSource }
                if selectedGoal.isAppleMapsPlace && selectedGoal.id == landmark.id { return selectedGoal }
                return landmark
            }
            let source = normalized(selectedSource, role: "source", landmarks: landmarks)
            let goal = normalized(selectedGoal, role: "goal", landmarks: landmarks)
            // The direct walk establishes the endpoint entrances. Additional walks
            // sample campus corridors; their shared geometry determines junctions.
            var requests: [(id: EdgeID, from: CampusMapPoint, to: CampusMapPoint)] = [
                ("selected-journey", source, goal)
            ]
            requests += Self.connections.compactMap { id, fromID, toID in
                guard let from = landmarks.first(where: { $0.id == fromID }),
                      let to = landmarks.first(where: { $0.id == toID }) else { return nil }
                return (EdgeID(rawValue: id), from, to)
            }
            // Sample two nearby corridors for custom places. Overlapping paths
            // become shared segments, not duplicate building-to-building edges.
            for point in [source, goal] where !landmarks.contains(where: { $0.id == point.id }) {
                let nearest = landmarks.sorted {
                    (try? CourseGeometry.distance(from: point.coordinate, to: $0.coordinate)) ?? .infinity
                        < (try? CourseGeometry.distance(from: point.coordinate, to: $1.coordinate)) ?? .infinity
                }.prefix(2)
                for junction in nearest {
                    requests.append((EdgeID(rawValue: "link-\(point.id)-\(junction.id)"), point, junction))
                }
            }
            var anchors: [String: Coordinate] = [:]
            var paths: [PedestrianPath] = []
            var unavailable = 0
            for (index, request) in requests.enumerated() {
                try check(token)
                status = "Connecting walking paths · \(index + 1) of \(requests.count)"
                do {
                    let from = anchors[request.from.id] ?? request.from.coordinate
                    let to = anchors[request.to.id] ?? request.to.coordinate
                    let points = try await geometry(from: from, to: to, token: token)
                    guard let first = points.first, let last = points.last else { throw LoadError.unconnectedPin }
                    // Established entrance anchors must join closely. A different
                    // entrance on the opposite side of a building is not a junction.
                    if anchors[request.from.id] != nil,
                       try CourseGeometry.distance(from: from, to: first) > 8 { throw LoadError.unconnectedPin }
                    if anchors[request.to.id] != nil,
                       try CourseGeometry.distance(from: to, to: last) > 8 { throw LoadError.unconnectedPin }
                    anchors[request.from.id] = anchors[request.from.id] ?? first
                    anchors[request.to.id] = anchors[request.to.id] ?? last
                    try check(token)
                    paths.append(.init(id: request.id,
                        fromJunction: NodeID(rawValue: request.from.id), toJunction: NodeID(rawValue: request.to.id),
                        bidirectional: true, polyline: points))
                } catch {
                    try check(token)
                    if (error as? URLError)?.code == .timedOut { throw LoadError.serviceSlow }
                    unavailable += 1
                }
            }
            try check(token)
            guard !paths.isEmpty else { throw LoadError.noWalkingPaths }
            if let startEntrance = anchors[source.id], let goalEntrance = anchors[goal.id],
               try CourseGeometry.distance(from: startEntrance, to: goalEntrance) < 4 {
                throw LoadError.sameEntrance
            }
            guard let sourceEntrance = anchors[source.id], let goalEntrance = anchors[goal.id] else {
                throw LoadError.unconnectedPin
            }
            let network = try WalkingJunctionNetwork(paths: paths,
                source: .init(id: NodeID(rawValue: source.id), name: "Start entrance", coordinate: sourceEntrance,
                    stoppingNote: "Apple Maps walking access for the selected start."),
                goal: .init(id: NodeID(rawValue: goal.id), name: "Destination entrance", coordinate: goalEntrance,
                    stoppingNote: "Apple Maps walking access for the selected destination."))
            let pinGap = try [source, goal].map { point in
                try CourseGeometry.distance(from: point.coordinate, to: anchors[point.id] ?? point.coordinate)
            }.max() ?? 0
            let baseline = try CampusLabExperiment(from: source, to: goal, nodes: network.nodes, paths: network.paths,
                unavailablePathCount: unavailable, selectedPinGapMetres: pinGap)
            guard CampusLabExperiment.routeCost(baseline.dijkstra) != nil else { throw LoadError.unconnectedPin }
            experiment = closedPathID == nil ? baseline : try CampusLabExperiment(
                from: source, to: goal, nodes: network.nodes, paths: network.paths, closedPathID: closedPathID,
                unavailablePathCount: unavailable, selectedPinGapMetres: pinGap)
            status = "\(network.nodes.count - 2) path junctions · \(network.paths.count) walking connections"
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            errorMessage = (error as? LoadError)?.message ?? "Walking paths could not be loaded. Check your connection and try again."
            status = "Journey needs another try"
        }
    }

    private func check(_ token: UUID) throws {
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
    }

    private func geometry(from: Coordinate, to: Coordinate, token: UUID) async throws -> [Coordinate] {
        let forward = key(from) + ":" + key(to)
        let reverse = key(to) + ":" + key(from)
        if let cached = cache[forward] { return cached }
        if let cached = cache[reverse] { return cached.reversed() }
        let geometry = try await provider(from, to)
        try check(token)
        guard geometry.count >= 2, let first = geometry.first, let last = geometry.last,
              try CourseGeometry.length(of: geometry) > 0,
              try CourseGeometry.distance(from: from, to: first) <= 60,
              try CourseGeometry.distance(from: to, to: last) <= 60 else {
            throw LoadError.unconnectedPin
        }
        cache[forward] = geometry
        return geometry
    }

    private func key(_ point: Coordinate) -> String {
        "\(point.latitude.bitPattern)-\(point.longitude.bitPattern)"
    }

    private func normalized(_ point: CampusMapPoint, role: String, landmarks: [CampusMapPoint]) -> CampusMapPoint {
        if let junction = landmarks.first(where: {
            $0.coordinate == point.coordinate
        }) { return junction }
        return CampusMapPoint(id: "selected-\(role)", name: point.name, coordinate: point.coordinate,
            address: point.address, isAppleMapsPlace: point.isAppleMapsPlace)
    }

    // These place pairs sample footways; they do not define the displayed graph.
    // WalkingJunctionNetwork derives topology from their shared route geometry.
    private static let connections = [
        ("jms-gardens", "01-jms", "02-lilybank-gardens"),
        ("gardens-house", "02-lilybank-gardens", "03-lilybank-house"),
        ("house-rejoin", "03-lilybank-house", "05-rejoin"),
        ("gardens-hetherington", "02-lilybank-gardens", "04-hetherington"),
        ("hetherington-rejoin", "04-hetherington", "05-rejoin"),
        ("rejoin-fraser", "05-rejoin", "06-fraser"),
        ("fraser-library", "06-fraser", "07-library")
    ]

    private enum LoadError: Error {
        case outsideCampus, samePoint, sameEntrance, noWalkingPaths, unconnectedPin, serviceSlow
        var message: String {
            switch self {
            case .outsideCampus: "Keep both pins inside the Gilmorehill campus area."
            case .samePoint: "Choose two different points, at least a few steps apart."
            case .sameEntrance: "Both pins connect to the same walking entrance. Move one pin farther away and try again."
            case .noWalkingPaths: "Apple Maps could not return walking paths. Check your connection and try again."
            case .unconnectedPin: "A pin could not connect to the walking network. Move it closer to a campus path and try again."
            case .serviceSlow: "Apple Maps is taking too long to return a walking path. Try the journey again."
            }
        }
    }
}

@MainActor
private final class CampusWalkingDirections {
    private var current: MKDirections?
    private var requestID = UUID()

    func cancel() { current?.cancel(); current = nil }

    func route(from: Coordinate, to: Coordinate) async throws -> [Coordinate] {
        let request = MKDirections.Request()
        request.source = mapItem(from)
        request.destination = mapItem(to)
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        let token = UUID()
        requestID = token
        current = directions
        var timedOut = false
        let watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard self?.requestID == token else { return }
            timedOut = true
            self?.cancel()
        }
        defer {
            watchdog.cancel()
            if current === directions { current = nil }
        }
        let response: MKDirections.Response
        do {
            response = try await withTaskCancellationHandler {
                try await directions.calculate()
            } onCancel: {
                Task { @MainActor [weak self] in
                    // Cancelling a replaced task must not cancel its successor.
                    if self?.requestID == token { self?.cancel() }
                }
            }
        } catch {
            if timedOut { throw URLError(.timedOut) }
            throw error
        }
        try Task.checkCancellation()
        guard let route = response.routes.min(by: { $0.distance < $1.distance }), route.polyline.pointCount >= 2 else {
            throw MKError(.directionsNotFound)
        }
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: route.polyline.pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        return coordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func mapItem(_ point: Coordinate) -> MKMapItem {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            return MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil)
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: point.latitude, longitude: point.longitude)))
        }
        #else
        // The macOS 15 contract runner can use an SDK that predates this initializer.
        return MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: point.latitude, longitude: point.longitude)))
        #endif
    }
}
