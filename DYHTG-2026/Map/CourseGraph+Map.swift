import AlgorithmArenaCore
import CoreLocation
import MapKit
import SwiftUI

extension Coordinate {
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension RouteBranch {
    var title: String {
        switch self {
        case .standard: "Standard"
        case .bonus: "Bonus"
        }
    }
}

extension CourseGraph {
    func node(_ id: NodeID) -> CourseNode? {
        nodes.first { $0.id == id }
    }

    func route(_ branch: RouteBranch) -> CourseRoute? {
        routes.first { $0.branch == branch }
    }

    func placeName(_ id: NodeID) -> String {
        guard let name = node(id)?.name else { return id.rawValue }
        return name.components(separatedBy: " — ").first ?? name
    }

    func stopTitle(_ id: NodeID) -> String {
        switch id {
        case stops.start: "Start"
        case stops.first: "Checkpoint 1"
        case stops.standardMiddle: "Checkpoint 2"
        case stops.bonusMiddle: "Bonus Checkpoint"
        case stops.third: "Checkpoint 3"
        case stops.finish: "Finish"
        default: placeName(id)
        }
    }

    func middleStop(for branch: RouteBranch) -> NodeID {
        branch == .bonus ? stops.bonusMiddle : stops.standardMiddle
    }

    func coordinates(along edgeIDs: [EdgeID], from origin: NodeID) -> [CLLocationCoordinate2D] {
        var current = origin
        var points: [Coordinate] = node(origin).map { [$0.coordinate] } ?? []
        for id in edgeIDs {
            guard let edge = edges.first(where: { $0.id == id }) else { continue }
            if edge.from == current {
                points.append(contentsOf: edge.polyline.dropFirst())
                current = edge.to
            } else {
                points.append(contentsOf: edge.polyline.reversed().dropFirst())
                current = edge.from
            }
        }
        return points.map(\.location)
    }

    func coordinates(for branch: RouteBranch) -> [CLLocationCoordinate2D] {
        coordinates(along: route(branch)?.edgeIDs ?? [], from: stops.start)
    }

    func divergingCoordinates(for branch: RouteBranch) -> [CLLocationCoordinate2D] {
        let other = Set(route(branch == .bonus ? .standard : .bonus)?.edgeIDs ?? [])
        var node = stops.start
        var origin: NodeID?
        var diverging: [EdgeID] = []
        for id in route(branch)?.edgeIDs ?? [] {
            guard let edge = edges.first(where: { $0.id == id }) else { continue }
            if !other.contains(id) {
                if origin == nil { origin = node }
                diverging.append(id)
            }
            node = edge.from == node ? edge.to : edge.from
        }
        return origin.map { coordinates(along: diverging, from: $0) } ?? []
    }
}

extension CourseGraph {
    func camera(from origin: NodeID, to target: NodeID) -> MapCamera {
        guard let from = node(origin)?.coordinate, let to = node(target)?.coordinate else {
            return MapCamera(centerCoordinate: CLLocationCoordinate2D(), distance: 1200, heading: 0, pitch: 60)
        }
        let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (from.latitude + to.latitude) / 2,
            longitude: (from.longitude + to.longitude) / 2
        )
        return MapCamera(
            centerCoordinate: center,
            distance: max(start.distance(from: end) * 5, 900),
            heading: bearing(from: from, to: to),
            pitch: 50
        )
    }

    private func bearing(from: Coordinate, to: Coordinate) -> CLLocationDirection {
        let radians = Double.pi / 180
        let deltaLongitude = (to.longitude - from.longitude) * radians
        let y = sin(deltaLongitude) * cos(to.latitude * radians)
        let x = cos(from.latitude * radians) * sin(to.latitude * radians)
            - sin(from.latitude * radians) * cos(to.latitude * radians) * cos(deltaLongitude)
        let degrees = atan2(y, x) / radians
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
