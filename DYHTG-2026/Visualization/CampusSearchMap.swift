import AlgorithmArenaCore
import MapKit
import SwiftUI

/// The real campus remains the primary canvas. Insets are supplied by the sheet
/// so MapKit keeps both its camera fitting and its attribution in the visible area.
struct CampusSearchMap: View {
    let experiment: CampusLabExperiment?
    let playback: ReplayPlayback?
    let start: CampusMapPoint
    let destination: CampusMapPoint
    let selection: SelectedEndpoint?
    let cameraRequest: Int
    var bottomInset: CGFloat = 300
    var showsControls = true
    let onSelect: (Coordinate) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleCamera: MapCamera?
    @State private var isThreeDimensional = false
    @State private var routeProgress = 0.0

    private var presentation: SearchPresentation? { playback?.presentation }
    private var routeColor: Color { colorScheme == .dark ? ArenaPalette.mint : ArenaPalette.teal }
    private var activeEdge: CourseEdge? {
        guard let pair = playback?.highlightedEdge, let cost = playback?.highlightedEdgeCost else { return nil }
        return experiment?.graph.edges.filter {
            (($0.from == pair.from && $0.to == pair.to) || ($0.bidirectional && $0.to == pair.from && $0.from == pair.to))
                && $0.costMetres == cost
        }.min { $0.id < $1.id }
    }
    private var predecessorEdges: [CourseEdge] {
        guard let playback, let experiment else { return [] }
        var seen: Set<EdgeID> = []
        return playback.step.state.costs.compactMap { node in
            guard let predecessor = node.predecessor,
                  let edge = experiment.edges(for: [predecessor, node.nodeID]).first,
                  seen.insert(edge.id).inserted else { return nil }
            return edge
        }
    }
    private var finalSegments: [CampusRouteSegment] {
        guard let experiment, let presentation else { return [] }
        return zip(presentation.routeNodes, presentation.routeNodes.dropFirst()).compactMap { from, to in
            guard let edge = experiment.edges(for: [from, to]).first else { return nil }
            let points = edge.from == from ? edge.polyline : Array(edge.polyline.reversed())
            return CampusRouteSegment(id: edge.id.rawValue, coordinates: points.map(\.location))
        }
    }
    private var revealedSegments: [CampusRouteSegment] {
        let segments = finalSegments
        var remaining = segments.reduce(0) { $0 + $1.length } * routeProgress
        return segments.compactMap { segment in
            guard remaining > 0 else { return nil }
            let result = segment.prefix(distance: remaining)
            remaining -= segment.length
            return result
        }
    }
    private var routeAnimationID: String {
        "\(experiment?.scenario.id.rawValue ?? "loading"):\(playback?.trace.algorithm.rawValue ?? "none"):\(presentation?.routeNodes.map(\.rawValue).joined(separator: ">") ?? ""):\(scenePhase == .active)"
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                networkContent
                searchContent
                placeContent
                endpointContent
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .automatic, pointsOfInterest: .including([.university, .library])))
            .mapControlVisibility(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomInset).allowsHitTesting(false)
            }
            .onTapGesture { point in
                guard selection != nil, let coordinate = proxy.convert(point, from: .local) else { return }
                onSelect(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
            .overlay(alignment: .bottomTrailing) {
                if showsControls {
                    cameraControls
                        .padding(.trailing, 16)
                        .padding(.bottom, bottomInset + 38)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleCamera = context.camera
                isThreeDimensional = context.camera.pitch > 10
            }
            .onChange(of: cameraRequest, initial: true) { _, _ in fitNetwork() }
            .onChange(of: experiment?.scenario.id) { _, _ in fitNetwork() }
            .task(id: routeAnimationID) { await revealRoute() }
        }
    }

    @MapContentBuilder
    private var networkContent: some MapContent {
        if let experiment {
            ForEach(experiment.graph.edges, id: \.id) { edge in
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.32) : Color(.systemGray).opacity(0.7),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(experiment.previousEdges, id: \.id) { edge in
                MapPolyline(coordinates: edge.polyline.map(\.location))
                    .stroke(routeColor.opacity(0.3), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 7]))
            }
            if let closed = experiment.closedPath {
                MapPolyline(coordinates: closed.polyline.map(\.location))
                    .stroke(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [3, 6]))
            }
        }
    }

    @MapContentBuilder
    private var searchContent: some MapContent {
        ForEach(predecessorEdges, id: \.id) { edge in
            MapPolyline(coordinates: edge.polyline.map(\.location))
                .stroke(routeColor.opacity(finalSegments.isEmpty ? 0.55 : 0.18), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        if let edge = activeEdge {
            MapPolyline(coordinates: edge.polyline.map(\.location))
                .stroke(ArenaPalette.amber.opacity(0.22), style: StrokeStyle(lineWidth: 17, lineCap: .round))
            MapPolyline(coordinates: edge.polyline.map(\.location))
                .stroke(ArenaPalette.amber, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        ForEach(revealedSegments) { segment in
            MapPolyline(coordinates: segment.coordinates)
                .stroke(routeColor.opacity(0.2), style: StrokeStyle(lineWidth: 19, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: segment.coordinates)
                .stroke(colorScheme == .dark ? ArenaPalette.ink : Color.white,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: segment.coordinates)
                .stroke(routeColor, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        if routeProgress > 0, routeProgress < 1, let tip = revealedSegments.last?.coordinates.last {
            Annotation("Tracing shortest route", coordinate: tip) {
                Circle().fill(Color.white).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(ArenaPalette.teal, lineWidth: 2))
                    .shadow(color: routeColor, radius: 7)
                    .allowsHitTesting(false)
            }
            .annotationTitles(.hidden)
        }
    }

    @MapContentBuilder
    private var placeContent: some MapContent {
        if let experiment {
            ForEach(experiment.places.filter {
                !isUnderEndpoint($0.coordinate)
            }) { place in
                Annotation(place.name, coordinate: place.coordinate.location) {
                    Button {
                        if selection != nil { onSelect(place.coordinate) }
                    } label: {
                        CampusSearchMarker(
                            place: place, summary: presentation?.summary(place.id),
                            stepIndex: playback?.index ?? 0
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(place.letter), \(place.name)")
                    .accessibilityIdentifier("visualize.map.node.\(place.letter)")
                }
                .annotationTitles(.hidden)
            }
        }
    }

    @MapContentBuilder
    private var endpointContent: some MapContent {
        Annotation("Start: \(start.name)", coordinate: startMapCoordinate.location, anchor: .bottom) {
            Button {
                if selection != nil { onSelect(start.coordinate) }
            } label: {
                CampusEndpointPin(
                    letter: endpointLetter(.source) ?? "S", title: "Start",
                    color: ArenaPalette.mint, isSelected: selection == .source
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start, \(start.name)")
            .accessibilityIdentifier("visualize.map.start")
        }
        .annotationTitles(.hidden)
        Annotation("Destination: \(destination.name)", coordinate: destinationMapCoordinate.location, anchor: .bottom) {
            Button {
                if selection != nil { onSelect(destination.coordinate) }
            } label: {
                CampusEndpointPin(
                    letter: endpointLetter(.goal) ?? "G", title: "Goal",
                    color: ArenaPalette.amber, isSelected: selection == .goal
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Destination, \(destination.name)")
            .accessibilityIdentifier("visualize.map.destination")
        }
        .annotationTitles(.hidden)
    }

    private var cameraControls: some View {
        ArenaGlassGroup(spacing: 10) {
            cameraControlButtons
        }
    }

    private var cameraControlButtons: some View {
        VStack(spacing: 10) {
            Button {
                guard let visibleCamera else { return }
                withAnimation(.easeInOut(duration: 0.65)) {
                    camera = .camera(MapCamera(
                        centerCoordinate: visibleCamera.centerCoordinate,
                        distance: visibleCamera.distance,
                        heading: visibleCamera.heading,
                        pitch: isThreeDimensional ? 0 : 50
                    ))
                }
            } label: {
                Text(isThreeDimensional ? "2D" : "3D")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 26)
            }
            .accessibilityLabel(isThreeDimensional ? "Show flat map" : "Show campus in 3D")
            .accessibilityIdentifier("visualize.map.perspective")
            Button { fitNetwork() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 26)
            }
            .accessibilityLabel("Fit campus network")
            .accessibilityIdentifier("visualize.map.recenter")
        }
        .foregroundStyle(.primary)
        .buttonStyle(ArenaCompactButtonStyle(shape: .circle))
    }

    private func endpointLetter(_ endpoint: SelectedEndpoint) -> String? {
        guard let experiment else { return nil }
        let id = endpoint == .source ? experiment.scenario.source : experiment.scenario.goal
        return experiment.place(id)?.letter
    }

    private var startMapCoordinate: Coordinate {
        start.coordinate
    }

    private var destinationMapCoordinate: Coordinate {
        destination.coordinate
    }

    private func isUnderEndpoint(_ coordinate: Coordinate) -> Bool {
        let point = MKMapPoint(coordinate.location)
        return point.distance(to: MKMapPoint(startMapCoordinate.location)) < 8
            || point.distance(to: MKMapPoint(destinationMapCoordinate.location)) < 8
    }

    private func fitNetwork() {
        let coordinates = [start.coordinate, destination.coordinate]
            + (experiment?.graph.edges.flatMap(\.polyline) ?? [])
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate.location)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        guard !rect.isNull else { return }
        // Give raised endpoint pins and the page masthead breathing room.
        let minMapPoints = 180 / MKMetersPerMapPointAtLatitude(start.coordinate.latitude)
        let horizontal = max(rect.width * 0.23, minMapPoints * 0.18)
        let vertical = max(rect.height * 0.30, minMapPoints * 0.30)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) {
            camera = .rect(rect.insetBy(dx: -horizontal, dy: -vertical))
        }
    }

    @MainActor
    private func revealRoute() async {
        routeProgress = 0
        guard !finalSegments.isEmpty else { return }
        guard scenePhase == .active, !reduceMotion else { routeProgress = 1; return }
        // Finite animation: cancellation on a new route, tab removal or background
        // never leaves a display timer or a perpetually pulsing overlay running.
        for frame in 1...45 {
            do { try await Task.sleep(for: .milliseconds(35)) } catch { return }
            guard !Task.isCancelled else { return }
            routeProgress = Double(frame) / 45
        }
    }
}

private struct CampusSearchMarker: View {
    let place: CampusLabPlace
    let summary: NodeSummary?
    let stepIndex: Int

    private var state: NodeSearchState { summary?.state ?? .undiscovered }
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        switch state {
        case .current: ArenaPalette.amber
        case .route, .frontier: ArenaPalette.mint
        case .settled: Color(.systemGray3)
        case .undiscovered: Color(.separator)
        }
    }
    private var fill: Color {
        switch state {
        case .current, .route: accent
        case .frontier: colorScheme == .dark ? ArenaPalette.teal : Color(.systemBackground)
        case .settled: Color(.secondarySystemBackground)
        case .undiscovered: Color(.systemBackground)
        }
    }

    var body: some View {
        ZStack {
            if state == .current {
                Image(systemName: "circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(ArenaPalette.amber.opacity(0.22))
                    .symbolEffect(.pulse, options: .repeat(2), value: stepIndex)
            }
            Text(place.letter)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state == .current || state == .route ? ArenaPalette.ink : Color.primary)
                .frame(width: 23, height: 23)
                .background(fill, in: Circle())
                .overlay(Circle().strokeBorder(accent, style: StrokeStyle(
                    lineWidth: state == .undiscovered ? 0.75 : 1.5,
                    dash: state == .frontier ? [3, 2] : []
                )))
        }
        .frame(width: 34, height: 34)
        .animation(.easeInOut(duration: 0.25), value: state)
        .accessibilityValue(state.title)
    }
}

private struct CampusEndpointPin: View {
    let letter: String
    let title: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(letter)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(color, in: Circle())
                    .foregroundStyle(ArenaPalette.ink)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.trailing, 5)
            }
            .padding(4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? color : Color(.separator).opacity(0.55), lineWidth: isSelected ? 1.5 : 0.5))
            Rectangle().fill(Color(.secondaryLabel)).frame(width: 1.5, height: 9)
            Circle().fill(color).frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1))
        }
        .padding(.bottom, -4)
    }
}

/// Trimming is performed within each returned walking polyline independently.
/// Adjacent MapKit paths can snap to different footway points; never join the gap.
private struct CampusRouteSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]

    var length: Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) {
            $0 + MKMapPoint($1.0).distance(to: MKMapPoint($1.1))
        }
    }

    func prefix(distance: Double) -> CampusRouteSegment? {
        guard let first = coordinates.first, coordinates.count > 1, distance > 0 else { return nil }
        if distance >= length { return self }
        var result = [first]
        var remaining = distance
        for (from, to) in zip(coordinates, coordinates.dropFirst()) {
            let a = MKMapPoint(from)
            let b = MKMapPoint(to)
            let segmentLength = a.distance(to: b)
            if remaining >= segmentLength {
                result.append(to)
                remaining -= segmentLength
            } else {
                let fraction = segmentLength > 0 ? remaining / segmentLength : 0
                result.append(MKMapPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction).coordinate)
                break
            }
        }
        return CampusRouteSegment(id: id, coordinates: result)
    }
}
