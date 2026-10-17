import AlgorithmArenaCore
import SwiftUI

struct MatchPanel: View {
    @Bindable var store: MatchStore
    let location: LocationProvider
    let paths: WalkingPaths
    let showsDetails: Bool
    @Binding var headerHeight: CGFloat
    @Binding var modal: MatchModal?
    @Binding var reviewed: Set<ChallengeID>

    @State private var isCheckingIn = false
    @State private var checkInFailure: LocationProvider.Failure?
    @State private var isConfirmingLeave = false

    private var course: CourseGraph { store.course }
    private var opponentName: String { store.opponent?.nickname ?? "the other player" }

    var body: some View {
        if let viewer = store.viewer {
            VStack(spacing: 0) {
                header(for: viewer)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        headerHeight = height
                    }
                if showsDetails {
                    details(for: viewer)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .sheet(item: $modal) { modal in
                content(for: modal)
            }
            .confirmationDialog("Leave the match?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                Button("Leave Match", role: .destructive) {
                    Task { await store.leave() }
                }
            } message: {
                Text("The match ends as incomplete for both players. Losing signal doesn't count as leaving.")
            }
            .actionErrorAlert(
                $store.actionError,
                retry: { Task { await store.retryPendingCommand() } },
                cancel: { store.discardPendingCommand() }
            )
            .checkInFailureAlert($checkInFailure) {
                if case .walking(let target) = viewer.stage { checkIn(at: target) }
            }
        }
    }

    private func details(for viewer: PlayerProgress) -> some View {
        List {
            Section {
                Scoreboard(viewer: viewer, opponent: store.opponent)
            } header: {
                Text("Match points")
            } footer: {
                Text(pointsSummary(viewer) + " Walking speed earns no points. Learning XP is separate.")
            }

            if let feedback = store.snapshot?.viewer.feedback, !feedback.isEmpty {
                Section("Feedback") {
                    ForEach(feedback, id: \.challengeID) { item in
                        if let challenge = store.challenges[item.challengeID] {
                            Button {
                                reviewed.insert(item.challengeID)
                                modal = .challenge(item.challengeID)
                            } label: {
                                LabeledContent(challenge.slot.title, value: status(of: item))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                }
            }

            if let room = store.snapshot?.room {
                Section {
                    LabeledContent("Algorithm", value: room.algorithm.title)
                    Text(room.algorithm.rule)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if case .walking(let target) = viewer.stage {
                Section {
                    Button("Ask an Organiser to Check You In") { modal = .organiser(target) }
                } footer: {
                    Text("Use this if your location can't be confirmed at \(course.stopTitle(target)).")
                }
            }

            Section {
                Button("Leave Match", role: .destructive) { isConfirmingLeave = true }
            } footer: {
                if course.readiness != .surveyed {
                    Text("Paths and stopping points are estimates until the course has been walked and checked.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    private func header(for viewer: PlayerProgress) -> some View {
        let step = nextStep(for: viewer)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(step.eyebrow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(step.title)
                    .font(.title2.weight(.bold))
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            primaryAction(for: viewer)
                .controlSize(.large)
        }
    }

    @ViewBuilder
    private func primaryAction(for viewer: PlayerProgress) -> some View {
        switch viewer.stage {
        case .practice:
            challengeButton("Start Warm-up")
        case .walking(let target):
            if location.isDenied {
                PrimaryButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                PrimaryButton(title: "Check In", busyTitle: "Checking In...", isBusy: isCheckingIn) {
                    checkIn(at: target)
                }
            }
        case .challenge(let id):
            PrimaryButton(title: "Answer Question") { modal = .challenge(id) }
        case .choosingRoute:
            PrimaryButton(title: "Choose Route") { modal = .routeChoice }
        case .finished:
            if store.availableChallenge?.slot == .learningCheck {
                challengeButton("Take Understanding Check")
            }
        case .departed, .atStart:
            EmptyView()
        }
    }

    @ViewBuilder
    private func challengeButton(_ title: String) -> some View {
        if let challenge = store.availableChallenge {
            PrimaryButton(title: title) { modal = .challenge(challenge.id) }
        }
    }

    private func nextStep(for viewer: PlayerProgress) -> (eyebrow: String, title: String, detail: String) {
        switch viewer.stage {
        case .practice:
            return ("Before you set off", "Warm-up Question", "Unscored. It shows how the search picks its next node.")
        case .walking(let target):
            let eyebrow = target == course.stops.finish ? "Last stretch" : "Next stop · \(course.stopTitle(target))"
            return (eyebrow, course.placeName(target), walkingDetail(to: target) + pendingSuffix(viewer))
        case .challenge(let id):
            let place = course.placeName(viewer.arrivals.last?.nodeID ?? course.stops.start)
            return (store.challenges[id]?.slot.title ?? "Checkpoint", "Question Waiting", "You've checked in at \(place).")
        case .choosingRoute:
            return ("Checkpoint 2", "Choose Your Route", "Standard: 20 points. Bonus: 40 points. Choose before seeing the question." + pendingSuffix(viewer))
        case .finished:
            return ("Finish", "You've Finished", finishedDetail)
        case .departed, .atStart:
            return ("Match", "Match Over", "This match won't count.")
        }
    }

    private func pendingSuffix(_ viewer: PlayerProgress) -> String {
        guard viewer.pendingRewardMaximum > 0 else { return "" }
        return " Your last answer is locked in until \(opponentName) answers."
    }

    private func walkingDetail(to target: NodeID) -> String {
        if location.isDenied {
            return "Location is off. Turn it on, or ask an organiser to check you in."
        }
        guard let latest = location.latest, let coordinate = course.node(target)?.coordinate,
            let distance = location.distance(to: coordinate)
        else {
            return "Finding your location..."
        }
        let away = Measurement(value: distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        if latest.horizontalAccuracy > course.arrivalPolicy.maximumHorizontalAccuracyMetres {
            return "\(away) away. GPS is imprecise here, so move into the open before checking in."
        }
        return "\(away) away. Check in when you get there."
    }

    private var finishedDetail: String {
        guard let result = store.snapshot?.room.result else {
            return "Your score is final. Waiting for \(opponentName) to finish."
        }
        switch result {
        case .winner(let playerID, _):
            return playerID == store.viewer?.id ? "You won the match." : "\(opponentName) won the match."
        case .draw:
            return "The match is a draw."
        case .incomplete:
            return "The match ended early."
        }
    }

    private func status(of item: FeedbackAvailability) -> String {
        guard case .released(let feedback) = item else {
            return "Waiting for \(opponentName)"
        }
        let mine = feedback.answers.first { $0.playerID == store.snapshot?.viewer.playerID }
        return mine?.isCorrect == true ? "Correct" : "Incorrect"
    }

    private func pointsSummary(_ viewer: PlayerProgress) -> String {
        let available = "\(viewer.remainingAvailablePoints) points still available."
        guard viewer.pendingRewardMaximum > 0 else { return available }
        return available + " Up to \(viewer.pendingRewardMaximum) more unlock when both players have answered."
    }

    @ViewBuilder
    private func content(for modal: MatchModal) -> some View {
        switch modal {
        case .challenge(let id):
            ChallengeView(store: store, challengeID: id)
        case .routeChoice:
            RouteChoiceSheet(course: course, paths: paths) { branch in
                await store.perform(.chooseRoute(branch: branch))
            }
        case .organiser(let target):
            OrganiserCheckInSheet(stopTitle: course.stopTitle(target)) { code in
                await arrive(at: target, evidence: .organiserApproval(approvalID: code))
            }
        }
    }

    private func checkIn(at target: NodeID) {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        Task {
            defer { isCheckingIn = false }
            do {
                let fix = try await location.currentFix()
                await arrive(at: target, evidence: .location(fix: fix))
            } catch let failure as LocationProvider.Failure {
                checkInFailure = failure
            } catch {
                checkInFailure = .unavailable
            }
        }
    }

    private func arrive(at target: NodeID, evidence: ArrivalEvidence) async {
        if target == course.stops.finish {
            await store.perform(.finish(evidence: evidence))
        } else {
            await store.perform(.confirmArrival(nodeID: target, evidence: evidence))
        }
        if case .challenge(let id) = store.viewer?.stage {
            modal = .challenge(id)
        }
    }
}

enum MatchModal: Identifiable {
    case challenge(ChallengeID)
    case routeChoice
    case organiser(NodeID)

    var id: String {
        switch self {
        case .challenge(let id): "challenge-\(id.rawValue)"
        case .routeChoice: "route"
        case .organiser(let node): "organiser-\(node.rawValue)"
        }
    }
}
