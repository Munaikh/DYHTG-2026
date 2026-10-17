import SwiftUI

struct RootView: View {
    @State private var duel = DuelStore()
    @State private var selectedTab = 0
    @AppStorage("onboardingCompleted.v1") private var onboardingCompleted = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            LearnHomeView()
                .tabItem { Label("Learn", systemImage: "book.closed.fill") }
                .tag(0)
            PlayHomeView(store: duel)
                .tabItem { Label("Play", systemImage: "bolt.shield.fill") }
                .badge(duel.snapshot?.phase == .answering && duel.viewer?.submitted == false ? "Your turn" : nil)
                .tag(1)
            VisualizeHomeView()
                .tabItem { Label("Visualize", systemImage: "map.fill") }
                .tag(2)
        }
        .tint(ArenaPalette.teal)
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { onboardingCompleted = !$0 }
        )) {
            OnboardingView { onboardingCompleted = true }
        }
        .onAppear {
            if duel.snapshot != nil || duel.pending != nil { selectedTab = 1 }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await duel.observe()
        }
    }
}
