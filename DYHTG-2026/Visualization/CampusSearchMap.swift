import AlgorithmArenaCore
import MapKit
import SwiftUI

struct CampusSearchMap: View {
    let experiment: CampusLabExperiment
    let playback: ReplayPlayback
    @State private var camera: MapCameraPosition = .automatic

    private var presentation: SearchPresentation { playback.presentation }
    private var activeEdge: CourseEdge? {
        guard let pair = playback.highlightedEdge else { return nil }
        return experiment.edges(for: [pair.from, pair.to]).first
    }
    private var predecessorEdges: [CourseEdge] {
        playback.step.state.costs.compactMap { node in
            guard let predecessor = node.predecessor else { return nil }
            return experiment.edges(for: [predecessor, node.nodeID]).first
        }
    }
    private var finalEdges: [CourseEdge] {
        experiment.edges(for: presentation.routeNodes)
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(experiment.graph.edges, id: \.id) { edge in
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(Color(.systemGray3), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            if let route = experiment.previousRoute {
                MapPolyline(coordinates: route.polyline.map(\.location))
                    .stroke(Color.teal.opacity(0.35), style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [5, 7]))
            }
            if let closed = experiment.closedPath {
                MapPolyline(coordinates: closed.polyline.map(\.location))
                    .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 6]))
            }
            ForEach(predecessorEdges, id: \.id) { edge in
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(Color.teal.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            if let edge = activeEdge {
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
            ForEach(finalEdges, id: \.id) { edge in
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(Color.teal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
            ForEach(experiment.places) { place in
                Annotation(place.name, coordinate: place.coordinate.location) {
                    CampusSearchMarker(
                        place: place,
                        summary: presentation.summary(place.id),
                        isStart: place.id == experiment.scenario.source,
                        isGoal: place.id == experiment.scenario.goal
                    )
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .overlay(alignment: .bottomTrailing) {
            Button {
                camera = .automatic
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Show entire campus network")
            .padding(12)
        }
        .accessibilityLabel("Campus search map. Nodes A to G. Use the graph view or search table for all route details.")
    }
}

private struct CampusSearchMarker: View {
    let place: CampusLabPlace
    let summary: NodeSummary?
    let isStart: Bool
    let isGoal: Bool

    private var state: NodeSearchState { summary?.state ?? .undiscovered }
    private var fill: Color {
        switch state {
        case .current: .orange
        case .route: .teal
        case .settled: Color(.systemGray4)
        case .frontier, .undiscovered: Color(.systemBackground)
        }
    }
    private var border: Color {
        switch state {
        case .current: .orange
        case .route, .frontier: .teal
        case .settled, .undiscovered: Color(.systemGray)
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(place.letter)
                .font(.caption.weight(.heavy))
                .foregroundStyle(state == .route || state == .current ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(fill, in: Circle())
                .overlay {
                    Circle().strokeBorder(border, style: StrokeStyle(lineWidth: 2.5, dash: state == .frontier ? [3, 2] : []))
                }
                .background(Circle().fill(Color(.systemBackground)).padding(-2))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            if isStart || isGoal {
                Text(isStart ? "START" : "GOAL")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place.letter), \(place.name)\(isStart ? ", start" : isGoal ? ", goal" : "")")
        .accessibilityValue("\(state.title), distance \(summary?.g.map(String.init) ?? "unknown") metres")
    }
}
