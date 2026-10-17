import AlgorithmArenaCore
import MapKit
import SwiftUI

struct MatchView: View {
    @Bindable var store: MatchStore

    @State private var location = LocationProvider()
    @State private var paths = WalkingPaths()
    @State private var camera: MapCameraPosition = .automatic
    @State private var isPanelPresented = true
    @State private var headerHeight: CGFloat = 180
    @State private var detent = PresentationDetent.height(220)
    @State private var modal: MatchModal?
    @State private var reviewed: Set<ChallengeID> = []
    @Environment(\.scenePhase) private var scenePhase

    private var compactDetent: PresentationDetent {
        .height(headerHeight)
    }

    private var readyFeedback: ChallengeDefinition? {
        let released = store.snapshot?.viewer.feedback.compactMap { item -> ChallengeID? in
            guard case .released(let feedback) = item, feedback.answers.count > 1 else { return nil }
            return feedback.challengeID
        }
        return released?
            .first { !reviewed.contains($0) }
            .flatMap { store.challenges[$0] }
    }

    var body: some View {
        if let viewer = store.viewer {
            CourseMapView(
                course: store.course,
                viewer: viewer,
                navigation: store.snapshot?.viewer.navigation,
                paths: paths,
                position: $camera
            )
            .safeAreaPadding(.bottom, headerHeight + 24)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    ScoreBadge(viewer: viewer, opponent: store.opponent)
                    if store.isReconnecting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reconnecting")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .floatingBackground()
                        .accessibilityElement(children: .combine)
                    }
                    if let challenge = readyFeedback {
                        FeedbackBanner(title: "\(challenge.slot.title) feedback is ready") {
                            reviewed.insert(challenge.id)
                            modal = .challenge(challenge.id)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.trailing, 56)
                .animation(.snappy, value: readyFeedback?.id)
            }
            .sheet(isPresented: $isPanelPresented) {
                MatchPanel(
                    store: store,
                    location: location,
                    paths: paths,
                    showsDetails: detent != compactDetent,
                    headerHeight: $headerHeight,
                    modal: $modal,
                    reviewed: $reviewed
                )
                .presentationDetents([compactDetent, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
            }
            .sensoryFeedback(.success, trigger: readyFeedback?.id)
            .onChange(of: headerHeight) {
                if detent != .medium && detent != .large { detent = compactDetent }
            }
            .onAppear {
                detent = compactDetent
                followLeg(viewer)
            }
            .onChange(of: store.snapshot?.viewer.navigation?.nextStop) {
                withAnimation(.easeInOut(duration: 1.2)) { followLeg(viewer) }
            }
            .task { await location.startUpdating() }
            .task(id: store.course.reference.version) { await paths.load(store.course) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await location.startUpdating() }
                } else {
                    location.stopUpdating()
                }
            }
            .onDisappear { location.stopUpdating() }
        }
    }
}

extension MatchView {
    private func followLeg(_ viewer: PlayerProgress) {
        let origin = viewer.arrivals.last?.nodeID ?? store.course.stops.start
        let target = store.snapshot?.viewer.navigation?.nextStop ?? store.course.stops.first
        camera = .camera(store.course.camera(from: origin, to: target))
    }
}

private struct ScoreBadge: View {
    let viewer: PlayerProgress
    let opponent: PlayerProgress?

    var body: some View {
        HStack(spacing: 6) {
            Text("You \(viewer.releasedScore)")
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(opponent?.nickname ?? "Other player") \(opponent?.releasedScore ?? 0)")
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .floatingBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score")
        .accessibilityValue("You \(viewer.releasedScore), \(opponent?.nickname ?? "other player") \(opponent?.releasedScore ?? 0)")
    }
}

private struct FeedbackBanner: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .floatingBackground()
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func floatingBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }
}
