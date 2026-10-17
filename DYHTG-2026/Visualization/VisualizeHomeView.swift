import AlgorithmArenaCore
import SwiftUI

struct VisualizeHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var journey: LabJourney = .library
    @State private var disruption: LabDisruption = .none
    @State private var algorithm: AlgorithmKind = .dijkstra
    @State private var showGraph = false
    @State private var speed = 1.0
    @State private var experiment: CampusLabExperiment?
    @State private var playback: ReplayPlayback?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    if let experiment, let playback {
                        experimentContent(experiment, playback: playback)
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("Search unavailable", systemImage: "map")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try again", action: loadExperiment)
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ProgressView("Preparing campus model")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Visualize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Journey", selection: $journey) {
                            ForEach(LabJourney.allCases) { route in
                                Text(route.title).tag(route)
                            }
                        }
                    } label: {
                        Label("Choose journey", systemImage: "map")
                    }
                    .accessibilityIdentifier("visualize.journey")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let playback {
                    LabPlaybackControls(playback: playback, speed: $speed, reduceMotion: reduceMotion)
                }
            }
            .tint(.teal)
            .onAppear { if experiment == nil { loadExperiment() } }
            .onDisappear { playback?.isPlaying = false }
            .onChange(of: journey) { _, _ in loadExperiment() }
            .onChange(of: disruption) { _, _ in loadExperiment() }
            .onChange(of: algorithm) { _, _ in resetAlgorithm() }
            .task(id: playbackTaskID) { await play() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("CAMPUS LAB", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(ArenaPalette.mint)
                Spacer()
                Image(systemName: "location.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(ArenaPalette.mint)
            }
            Text("See the search.")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(journey.routeLabel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArenaPalette.ink, in: .rect(cornerRadius: 24))
    }

    private func experimentContent(_ experiment: CampusLabExperiment, playback: ReplayPlayback) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Search algorithm", selection: $algorithm) {
                Text("Dijkstra").tag(AlgorithmKind.dijkstra)
                Text("A*").tag(AlgorithmKind.aStar)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("visualize.algorithm")

            VStack(spacing: 0) {
                HStack {
                    Text(showGraph ? "\(experiment.place(experiment.scenario.source)?.letter ?? "") start · \(experiment.place(experiment.scenario.goal)?.letter ?? "") goal · metres" : "Gilmorehill, Glasgow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Picker("View", selection: $showGraph) {
                        Image(systemName: "map").accessibilityLabel("Map").tag(false)
                        Image(systemName: "point.3.connected.trianglepath.dotted").accessibilityLabel("Graph").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    .accessibilityIdentifier("visualize.view")
                }
                .padding(12)
                if showGraph {
                    SearchGraphView(presentation: playback.presentation, highlightedEdge: playback.highlightedEdge)
                        .padding(.vertical, 12)
                        .frame(minHeight: 270)
                        .accessibilityIdentifier("visualize.graph")
                } else {
                    CampusSearchMap(experiment: experiment, playback: playback)
                        .id("\(journey.rawValue)-\(disruption.rawValue)")
                        .frame(height: 290)
                        .accessibilityIdentifier("visualize.map")
                }
                LabLegend(isGraph: showGraph)
                    .padding(12)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .clipShape(.rect(cornerRadius: 22))

            LabStepCard(experiment: experiment, playback: playback)

            twistCard

            LabComparison(experiment: experiment, isComplete: playback.index == playback.lastIndex)

            DisclosureGroup {
                LabSearchTable(experiment: experiment, presentation: playback.presentation)
                    .padding(.top, 10)
            } label: {
                Label("Node costs & campus places", systemImage: "tablecells")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))

            Text("An educational campus model with estimated paths and metre costs; outdoor survey pending.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var twistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "bolt.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change the world")
                        .font(.headline)
                    Text(disruption == .none ? "Close a path. Watch the algorithm adapt." : disruption.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if disruption == .none {
                Button {
                    disruption = .detour
                } label: {
                    Label("Close the Gardens path", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("visualize.twist")
            } else {
                Text(showGraph ? "Switch to Map to see the original route and closed path." : "Dashed mint = original route · red = closed path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reopen all paths") { disruption = .none }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("visualize.restore")
            }
            Menu {
                Picker("Campus conditions", selection: $disruption) {
                    ForEach(LabDisruption.allCases) { condition in
                        Text(condition.title).tag(condition)
                    }
                }
            } label: {
                Label("Try another condition", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
                    .frame(minHeight: 32)
            }
            .accessibilityIdentifier("visualize.conditions")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.07), in: .rect(cornerRadius: 22))
    }

    private var playbackTaskID: String {
        "\(journey.rawValue)-\(disruption.rawValue)-\(algorithm.rawValue)-\(playback?.isPlaying ?? false)-\(speed)-\(reduceMotion)"
    }

    private func loadExperiment() {
        playback?.isPlaying = false
        do {
            let next = try CampusLabExperiment(journey: journey, disruption: disruption)
            experiment = next
            playback = ReplayPlayback(trace: next.trace(for: algorithm), scenario: next.scenario)
            errorMessage = nil
        } catch {
            experiment = nil
            playback = nil
            errorMessage = "The campus model couldn't be prepared. Try restoring the default experiment."
        }
    }

    private func resetAlgorithm() {
        playback?.isPlaying = false
        guard let experiment else { loadExperiment(); return }
        playback = ReplayPlayback(trace: experiment.trace(for: algorithm), scenario: experiment.scenario)
    }

    @MainActor
    private func play() async {
        guard let playback, playback.isPlaying else { return }
        if playback.index == playback.lastIndex { playback.move(to: 0, animated: !reduceMotion) }
        while playback.index < playback.lastIndex {
            do { try await Task.sleep(for: .seconds(1.25 / speed)) }
            catch { return }
            guard !Task.isCancelled, playback.isPlaying else { return }
            playback.move(to: playback.index + 1, animated: !reduceMotion)
        }
        playback.isPlaying = false
    }
}

private struct LabPlaybackControls: View {
    @Bindable var playback: ReplayPlayback
    @Binding var speed: Double
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Step \(playback.index + 1) / \(playback.trace.steps.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Menu {
                    Picker("Playback speed", selection: $speed) {
                        Text("0.5× · Take your time").tag(0.5)
                        Text("1× · Normal").tag(1.0)
                        Text("2× · Fast").tag(2.0)
                    }
                } label: {
                    Text("\(speed.formatted())×")
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 44, minHeight: 32)
                }
                .accessibilityLabel("Playback speed, \(speed.formatted()) times")
                .accessibilityHint("Changes presentation pace, not algorithm performance")
                .accessibilityIdentifier("visualize.speed")
            }
            Slider(value: Binding(
                get: { Double(playback.index) },
                set: { value in
                    playback.isPlaying = false
                    playback.move(to: Int(value.rounded()), animated: false)
                }
            ), in: 0...Double(max(playback.lastIndex, 1)), step: 1)
            .accessibilityLabel("Search step")
            .accessibilityValue("\(playback.index + 1) of \(playback.trace.steps.count)")
            .accessibilityIdentifier("visualize.scrubber")
            HStack(spacing: 12) {
                stepButton("Restart search", symbol: "arrow.counterclockwise", index: 0)
                    .accessibilityIdentifier("visualize.restart")
                stepButton("Previous step", symbol: "backward.frame.fill", index: playback.index - 1)
                    .disabled(playback.index == 0)
                Button {
                    playback.isPlaying.toggle()
                } label: {
                    Label(playback.isPlaying ? "Pause" : playback.index == playback.lastIndex ? "Replay search" : "Run search",
                          systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("visualize.play")
                stepButton("Next step", symbol: "forward.frame.fill", index: playback.index + 1)
                    .disabled(playback.index == playback.lastIndex)
                    .accessibilityIdentifier("visualize.next")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private func stepButton(_ title: String, symbol: String, index: Int) -> some View {
        Button {
            playback.isPlaying = false
            playback.move(to: index, animated: !reduceMotion)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(title)
    }
}

#Preview {
    VisualizeHomeView()
}
