import AlgorithmArenaCore
import SwiftUI

/// A persistent map with an in-page sheet keeps the main tabs available during exploration.
struct VisualizeHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var loader = CampusRouteLoader()
    @State private var start = CampusMapPoint.start
    @State private var destination = CampusMapPoint.defaultDestination
    @State private var algorithm: AlgorithmKind = .dijkstra
    @State private var playback: ReplayPlayback?
    @State private var selection: SelectedEndpoint?
    @State private var destinationSheet: CampusEndpointSheet?
    @State private var expanded = false
    @GestureState private var sheetDrag: CGFloat = 0
    @State private var speed = 1.0
    @State private var retry = 0
    @State private var cameraRequest = 0
    @State private var closedPathID: EdgeID?
    @State private var selectionError: String?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let restingHeight = selection != nil ? 146.0 : expanded ? geometry.size.height * 0.86 : min(282, geometry.size.height * 0.48)
                let sheetHeight = min(max(restingHeight - sheetDrag, 140), geometry.size.height * 0.9)
                ZStack(alignment: .bottom) {
                    CampusSearchMap(
                        experiment: loader.experiment,
                        playback: playback,
                        start: start,
                        destination: destination,
                        selection: selection,
                        cameraRequest: cameraRequest,
                        bottomInset: sheetHeight + 8,
                        showsControls: !expanded || selection != nil,
                        onSelect: selectCoordinate
                    )
                    .ignoresSafeArea(edges: .top)
                    VStack {
                        mapHeader
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    routeSheet(height: sheetHeight)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: expanded)
                .animation(reduceMotion ? nil : .spring(response: 0.35), value: selection)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(ArenaPalette.ink)
            .tint(LearnStyle.teal)
            .sheet(item: $destinationSheet) { sheet in
                CampusEndpointPicker(
                    role: sheet.role,
                    current: sheet.role == .source ? start : destination,
                    choose: { point in setEndpoint(point, role: sheet.role) },
                    chooseOnMap: {
                        playback?.isPlaying = false
                        selectionError = nil
                        selection = sheet.role
                    }
                )
            }
            .task(id: requestID + String(scenePhase == .active)) {
                guard scenePhase == .active else { return }
                playback?.isPlaying = false
                playback = nil
                await loader.load(from: start, to: destination, closedPathID: closedPathID)
                guard !Task.isCancelled, let experiment = loader.experiment else { return }
                playback = ReplayPlayback(trace: experiment.trace(for: algorithm), scenario: experiment.scenario)
                cameraRequest += 1
            }
            .onChange(of: algorithm) { _, _ in resetPlayback() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    playback?.isPlaying = false
                    loader.cancel()
                }
            }
            .onDisappear {
                playback?.isPlaying = false
                loader.cancel()
            }
            .task(id: playbackTaskID) { await play() }
        }
    }

    private var mapHeader: some View {
        HStack {
            Spacer()
            ProfileButton(floating: true)
        }
    }

    private func routeSheet(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            sheetHandle
            if selection != nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectionError ?? "Tap a path or place on campus.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Cancel") { selection = nil; selectionError = nil }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("visualize.pin.cancel")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            endpointControls.id("route-controls")
                            if loader.isLoading {
                                HStack(spacing: 12) {
                                    ProgressView().tint(LearnStyle.teal)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Connecting walking paths").font(.subheadline.bold())
                                        Text(loader.status).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                .accessibilityIdentifier("visualize.loading")
                            } else if let error = loader.errorMessage {
                                errorCard(error)
                            } else if let experiment = loader.experiment, let playback {
                                searchAction(playback)
                                LabTransport(playback: playback, speed: $speed, reduceMotion: reduceMotion)
                                LabStepCard(experiment: experiment, playback: playback)
                                LabLegend(isGraph: false)
                                experimentDetails(experiment, playback: playback)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                        .contentShape(Rectangle())
                    }
                    .frame(height: max(height - 64, 1))
                    .contentShape(Rectangle())
                    .scrollIndicators(.hidden)
                    .accessibilityIdentifier("visualize.sheet.scroll")
                    .onChange(of: expanded) { _, isExpanded in
                        if !isExpanded { scroll.scrollTo("route-controls", anchor: .top) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(.regularMaterial, in: .rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 30))
        .contentShape(.rect(cornerRadius: 30))
        .shadow(color: .black.opacity(0.1), radius: 18, y: 4)
    }

    private var sheetHandle: some View {
        VStack(spacing: 8) {
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 34, height: 5)
                .padding(.top, 10)
            HStack {
                Text(selection == .source ? "Set your start" : selection == .goal ? "Set destination" : "Campus routes")
                    .font(.system(.title2, design: .default, weight: .bold))
                Spacer()
                if let playback, playback.index == playback.lastIndex,
                   let cost = CampusLabExperiment.routeCost(playback.trace), selection == nil {
                    Text("\(cost) m")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(LearnStyle.teal)
                }
                if selection == nil {
                    Button {
                        expanded.toggle()
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(.quaternary, in: Circle())
                    }
                    .accessibilityLabel(expanded ? "Show more map" : "Show search details")
                    .accessibilityIdentifier("visualize.sheet.expand")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .frame(height: 64)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8)
            .updating($sheetDrag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                guard selection == nil else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.35)) {
                    if value.predictedEndTranslation.height < -45 { expanded = true }
                    if value.predictedEndTranslation.height > 45 { expanded = false }
                }
            })
    }

    private var endpointControls: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                endpointRow(start, role: .source)
                Divider().padding(.leading, 39)
                endpointRow(destination, role: .goal)
            }
            Button {
                playback?.isPlaying = false
                let oldStart = start
                start = destination
                destination = oldStart
                closedPathID = nil
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 64)
                    .background(ArenaPalette.surface, in: Capsule())
            }
            .accessibilityLabel("Swap start and destination")
            .accessibilityIdentifier("visualize.swap")
        }
    }

    private func endpointRow(_ point: CampusMapPoint, role: SelectedEndpoint) -> some View {
        Button {
            playback?.isPlaying = false
            destinationSheet = CampusEndpointSheet(role: role)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: role == .source ? "circle.inset.filled" : "flag.checkered")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(role == .source ? ArenaPalette.teal : ArenaPalette.ink)
                    .frame(width: 28, height: 28)
                    .background(role == .source ? ArenaPalette.mint : ArenaPalette.amber, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(role == .source ? "START" : "DESTINATION")
                        .font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
                    Text(point.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.secondary)
            }
            .frame(minHeight: 43)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(role == .source ? "visualize.start" : "visualize.destination")
    }

    private func searchAction(_ playback: ReplayPlayback) -> some View {
        ArenaGlassGroup {
            HStack(spacing: 12) {
                Menu {
                    Picker("Search algorithm", selection: $algorithm) {
                        Text("Dijkstra").tag(AlgorithmKind.dijkstra)
                        Text("A*").tag(AlgorithmKind.aStar)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                        Text(algorithm == .dijkstra ? "Dijkstra" : "A*")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(height: 28)
                }
                .buttonStyle(ArenaCompactButtonStyle())
                .controlSize(.large)
                .accessibilityIdentifier("visualize.algorithm")
                Button { playback.isPlaying.toggle() } label: {
                    Label(playback.isPlaying ? "Pause" : playback.index == playback.lastIndex ? "Replay" : "Explore route",
                          systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ArenaActionStyle())
                .accessibilityIdentifier("visualize.play")
            }
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Paths unavailable", systemImage: "wifi.exclamationmark").font(.headline)
            Text(error).font(.subheadline).foregroundStyle(.secondary)
            Button("Try again") { retry += 1 }
                .buttonStyle(ArenaActionStyle())
                .accessibilityIdentifier("visualize.retry")
        }
        .arenaCard()
    }

    private func experimentDetails(_ experiment: CampusLabExperiment, playback: ReplayPlayback) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup {
                SearchGraphView(presentation: playback.presentation, highlightedEdge: playback.highlightedEdge,
                    highlightedEdgeCost: playback.highlightedEdgeCost)
                    .frame(minHeight: 320)
                    .padding(.top, 12)
                    .accessibilityIdentifier("visualize.graph")
                LabSearchTable(experiment: experiment, presentation: playback.presentation)
                    .padding(.top, 12)
            } label: {
                Label("Inside the algorithm", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
            }
            .arenaCard()
            LabComparison(experiment: experiment, isComplete: playback.index == playback.lastIndex)
            if closedPathID != nil || experiment.dijkstra.outcome.routeNodeIDs != nil {
                pathChallenge(experiment: experiment, route: experiment.dijkstra.outcome.routeNodeIDs ?? [])
            }
            Label("Walking geometry from Apple Maps", systemImage: "map.fill")
                .font(.caption.weight(.semibold))
            Text(experiment.geometryNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func pathChallenge(experiment: CampusLabExperiment, route: [NodeID]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Change the world", systemImage: "bolt.shield.fill")
                .font(.headline).foregroundStyle(LearnStyle.teal)
            Text(closedPathID == nil ? "Remove one network connection and see how the search adapts." : "One connection is removed from the graph. The dashed line remembers your original route.")
                .font(.subheadline).foregroundStyle(.secondary)
            if closedPathID != nil {
                Button("Restore connection") { closedPathID = nil }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .accessibilityIdentifier("visualize.restore")
            } else if let edge = experiment.edges(for: route).dropFirst().first ?? experiment.edges(for: route).first {
                Button("Remove a connection") { closedPathID = edge.id }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .accessibilityIdentifier("visualize.twist")
            }
        }
        .arenaCard()
    }

    private func selectCoordinate(_ coordinate: Coordinate) {
        guard let selection else { return }
        guard CampusMapPoint.contains(coordinate) else {
            selectionError = "Choose a point within Gilmorehill campus."
            return
        }
        setEndpoint(.init(id: UUID().uuidString, name: selection == .source ? "Dropped start pin" : "Dropped destination pin", coordinate: coordinate), role: selection)
        self.selection = nil
        selectionError = nil
        expanded = false
    }

    private func setEndpoint(_ point: CampusMapPoint, role: SelectedEndpoint) {
        playback?.isPlaying = false
        if role == .source { start = point } else { destination = point }
        closedPathID = nil
    }

    private var requestID: String {
        "\(start.coordinate.latitude),\(start.coordinate.longitude):\(destination.coordinate.latitude),\(destination.coordinate.longitude):\(closedPathID?.rawValue ?? "open"):\(retry)"
    }
    private var playbackTaskID: String {
        "\(requestID):\(algorithm.rawValue):\(playback?.isPlaying ?? false):\(speed):\(scenePhase)"
    }
    private func resetPlayback() {
        playback?.isPlaying = false
        guard let experiment = loader.experiment else { return }
        playback = ReplayPlayback(trace: experiment.trace(for: algorithm), scenario: experiment.scenario)
    }
    @MainActor private func play() async {
        guard let playback, playback.isPlaying, scenePhase == .active else { return }
        if playback.index == playback.lastIndex { playback.move(to: 0, animated: !reduceMotion) }
        while playback.index < playback.lastIndex {
            do { try await Task.sleep(for: .seconds(0.85 / speed)) } catch { return }
            guard !Task.isCancelled, playback.isPlaying else { return }
            playback.move(to: playback.index + 1, animated: !reduceMotion)
        }
        playback.isPlaying = false
    }
}

private struct LabTransport: View {
    @Bindable var playback: ReplayPlayback
    @Binding var speed: Double
    let reduceMotion: Bool

    var body: some View {
        ArenaGlassGroup {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Button {
                        playback.isPlaying = false
                        playback.move(to: 0, animated: !reduceMotion)
                    } label: {
                        Image(systemName: "arrow.counterclockwise").frame(width: 20, height: 26)
                    }
                    .buttonStyle(ArenaCompactButtonStyle())
                    .accessibilityLabel("Restart search").accessibilityIdentifier("visualize.restart")
                    Spacer()
                    Text("Step \(playback.index + 1) of \(playback.trace.steps.count)")
                        .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        playback.isPlaying = false
                        playback.move(to: playback.index + 1, animated: !reduceMotion)
                    } label: {
                        Image(systemName: "forward.frame.fill").frame(width: 20, height: 26)
                    }
                    .buttonStyle(ArenaCompactButtonStyle())
                    .disabled(playback.index == playback.lastIndex)
                    .accessibilityLabel("Next step").accessibilityIdentifier("visualize.next")
                }
                HStack {
                    Text("Search replay")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Playback speed", selection: $speed) {
                            Text("0.5×").tag(0.5)
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                            Text("4×").tag(4.0)
                        }
                    } label: { Text("\(speed.formatted())×").font(.caption.bold()) }
                    .accessibilityIdentifier("visualize.speed")
                }
                Slider(value: Binding(get: { Double(playback.index) }, set: {
                    playback.isPlaying = false
                    playback.move(to: Int($0.rounded()), animated: false)
                }), in: 0...Double(max(1, playback.lastIndex)), step: 1)
                .disabled(playback.lastIndex == 0)
                .accessibilityLabel("Search step")
                .accessibilityIdentifier("visualize.scrubber")
            }
        }
    }
}

private extension SearchOutcome {
    var routeNodeIDs: [NodeID]? {
        guard case .route(let nodes, _) = self else { return nil }
        return nodes
    }
}
