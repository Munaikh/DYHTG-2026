import AlgorithmArenaCore
import AlgorithmArenaFixtures

extension MatchStore {
    static func demo(timing: DemoMatchService.Timing = .init()) -> MatchStore {
        let course = (try? GilmorehillCourse.candidate()) ?? ArenaFixtures.course
        return MatchStore(course: course) {
            DemoMatchService(course: course, timing: timing)
        }
    }
}
