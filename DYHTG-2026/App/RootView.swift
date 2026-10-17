import SwiftUI

struct RootView: View {
    let store: MatchStore
    let learning: LearningStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch store.route {
            case .home:
                LearningShell(match: store, learning: learning)
                    .transition(.opacity)
            case .lobby:
                LobbyView(store: store)
                    .transition(.opacity)
            case .match:
                MatchView(store: store)
                    .transition(.opacity)
            case .results:
                ResultsView(store: store)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion || learning.profile.preferences.reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.route)
        .environment(\.arenaReduceMotion, reduceMotion || learning.profile.preferences.reduceMotion)
        .modifier(LearningNoticeModifier(learning: learning))
        .onChange(of: store.snapshot, initial: true) { _, snapshot in
            learning.recordMatch(snapshot, live: store.mode == .live)
        }
        .onChange(of: store.route) { _, route in
            if route == .home { learning.syncCampusNickname() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refresh() }
        }
    }
}
