import AlgorithmArenaFixtures

extension MatchStore {
    static func demo(timing: DemoMatchService.Timing = .init()) -> MatchStore {
        MatchStore(course: ArenaFixtures.course) {
            DemoMatchService(course: ArenaFixtures.course, timing: timing)
        }
    }
}
