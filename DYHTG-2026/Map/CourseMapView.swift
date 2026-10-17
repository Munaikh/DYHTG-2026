import AlgorithmArenaCore
import MapKit
import SwiftUI

struct CourseMapView: View {
    let course: CourseGraph
    let viewer: PlayerProgress
    let navigation: NavigationState?
    let paths: WalkingPaths
    @Binding var position: MapCameraPosition

    private var stops: [NodeID] {
        let middles = (viewer.routeChoice.map { [$0] } ?? RouteBranch.allCases).map(course.middleStop)
        return [course.stops.start, course.stops.first] + middles + [course.stops.third, course.stops.finish]
    }

    private var target: NodeID? {
        switch viewer.stage {
        case .walking(let node): node
        case .challenge: viewer.arrivals.last?.nodeID
        default: nil
        }
    }

    var body: some View {
        Map(position: $position) {
            MapPolyline(coordinates: paths.path(for: viewer.routeChoice ?? .standard, in: course))
                .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            if viewer.routeChoice == nil {
                MapPolyline(coordinates: paths.bonusDetour(in: course))
                    .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [1, 8]))
            }

            if let navigation, let origin = viewer.arrivals.last?.nodeID {
                let leg = paths.path(from: origin, to: navigation.nextStop, in: course, branch: viewer.routeChoice)
                MapPolyline(coordinates: leg)
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: leg)
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }

            ForEach(stops, id: \.self) { stop in
                if let node = course.node(stop) {
                    marker(for: stop, at: node.coordinate.location)
                }
            }

            UserAnnotation()
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapPitchToggle()
            MapCompass()
            MapScaleView()
        }
    }

    @MapContentBuilder
    private func marker(for stop: NodeID, at coordinate: CLLocationCoordinate2D) -> some MapContent {
        let title = course.stopTitle(stop)
        let visited = viewer.hasArrived(at: stop) && stop != target
        let tint: Color = stop == target ? Color.accent : visited ? Color(.systemGray3) : Color(.systemGray)

        if visited {
            Marker(title, systemImage: "checkmark", coordinate: coordinate)
                .tint(tint)
        } else if stop == course.stops.start {
            Marker(title, systemImage: "figure.walk", coordinate: coordinate)
                .tint(tint)
        } else if stop == course.stops.finish {
            Marker(title, systemImage: "flag.checkered", coordinate: coordinate)
                .tint(tint)
        } else if stop == course.stops.bonusMiddle {
            Marker(title, systemImage: "star.fill", coordinate: coordinate)
                .tint(tint)
        } else {
            Marker(title, monogram: Text(monogram(for: stop)), coordinate: coordinate)
                .tint(tint)
        }
    }

    private func monogram(for stop: NodeID) -> String {
        switch stop {
        case course.stops.first: "1"
        case course.stops.third: "3"
        default: "2"
        }
    }
}
