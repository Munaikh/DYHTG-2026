import SwiftUI

@main
struct DYHTG2026App: App {
    @State private var store = MatchStore.demo()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
