import AlgorithmArenaCore
import AlgorithmArenaFixtures
import SwiftUI

@main
struct DYHTG2026App: App {
    @State private var store: MatchStore = {
        let course = (try? GilmorehillCourse.candidate()) ?? ArenaFixtures.course
        return MatchStore(
            course: course,
            liveService: { SupabaseMatchService() },
            practiceService: { DemoMatchService(course: course) },
            persistence: .standard
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
