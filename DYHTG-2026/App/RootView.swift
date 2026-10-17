import SwiftUI

struct RootView: View {
    let store: MatchStore

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch store.route {
            case .home:
                HomeView(store: store)
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
        .animation(.easeInOut(duration: 0.25), value: store.route)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refresh() }
        }
    }
}
