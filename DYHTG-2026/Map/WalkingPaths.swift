import AlgorithmArenaCore
import MapKit
import Observation

@MainActor
@Observable
final class WalkingPaths {
    struct Leg: Hashable {
        let from: NodeID
        let to: NodeID
    }

    private(set) var legs: [Leg: [CLLocationCoordinate2D]] = [:]
    @ObservationIgnored private var loaded: CourseReference?

    func load(_ course: CourseGraph) async {
        guard loaded != course.reference else { return }
        loaded = course.reference
        legs = [:]
        for leg in Self.legs(in: course) {
            guard let from = course.node(leg.from)?.coordinate, let to = course.node(leg.to)?.coordinate,
                let path = await walkingPath(from: from, to: to)
            else { continue }
            legs[leg] = path
        }
    }

    func path(from origin: NodeID, to target: NodeID, in course: CourseGraph, branch: RouteBranch?) -> [CLLocationCoordinate2D] {
        legs[Leg(from: origin, to: target)]
            ?? course.legCoordinates(from: origin, to: target, branch: branch ?? .standard)
    }

    func path(for branch: RouteBranch, in course: CourseGraph) -> [CLLocationCoordinate2D] {
        let stops = course.stopSequence(for: branch)
        return zip(stops, stops.dropFirst()).flatMap { path(from: $0, to: $1, in: course, branch: branch) }
    }

    func bonusDetour(in course: CourseGraph) -> [CLLocationCoordinate2D] {
        let stops = course.stops
        return path(from: stops.first, to: stops.bonusMiddle, in: course, branch: .bonus)
            + path(from: stops.bonusMiddle, to: stops.third, in: course, branch: .bonus)
    }

    private static func legs(in course: CourseGraph) -> Set<Leg> {
        let sequences = RouteBranch.allCases.map(course.stopSequence)
        return Set(sequences.flatMap { stops in zip(stops, stops.dropFirst()).map { Leg(from: $0, to: $1) } })
    }

    private func walkingPath(from: Coordinate, to: Coordinate) async -> [CLLocationCoordinate2D]? {
        let request = MKDirections.Request()
        request.source = mapItem(at: from)
        request.destination = mapItem(at: to)
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        let polyline = route.polyline
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&points, range: NSRange(location: 0, length: polyline.pointCount))
        return [from.location] + points + [to.location]
    }

    private func mapItem(at coordinate: Coordinate) -> MKMapItem {
        if #available(iOS 26, *) {
            MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else {
            MKMapItem(placemark: MKPlacemark(coordinate: coordinate.location))
        }
    }
}
