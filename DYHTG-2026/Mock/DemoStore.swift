import AlgorithmArenaCore
import AlgorithmArenaFixtures

extension MatchStore {
    static func preview(timing: DemoMatchService.Timing = .init()) -> MatchStore {
        let course = (try? GilmorehillCourse.candidate()) ?? ArenaFixtures.course
        return MatchStore(
            course: course,
            liveService: { DemoMatchService(course: course, timing: timing) },
            practiceService: { DemoMatchService(course: course, timing: timing) }
        )
    }
}
