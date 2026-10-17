import AlgorithmArenaCore
import Foundation

@main @MainActor
struct CampusRouteChecks {
    enum Failure: Error { case offline }

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }

    static func main() async throws {
        var calls = 0
        let loader = CampusRouteLoader { from, to in
            calls += 1
            return [from, to]
        }
        let start = CampusMapPoint(id: "tap-start", name: "My start", coordinate: .init(latitude: 55.8718, longitude: -4.2930))
        let goal = CampusMapPoint(id: "tap-goal", name: "My destination", coordinate: .init(latitude: 55.8738, longitude: -4.2875))
        await loader.load(from: start, to: goal)
        let first = try require(loader.experiment)
        expect(first.places.count == 9, "Arbitrary points must become graph vertices")
        expect(first.routeTitle == "My start → My destination", "Selected point names must survive")
        expect(first.scenario.source == "selected-source" && first.scenario.goal == "selected-goal", "Dynamic source and goal")
        expect(CampusLabExperiment.routeCost(first.dijkstra) == CampusLabExperiment.routeCost(first.aStar), "Both algorithms must find optimal equal cost")
        expect(calls == 11, "Seven network edges and four endpoint links")
        print("PASS arbitrary selected endpoints and exact search graph")

        await loader.load(from: start, to: goal)
        expect(calls == 11 && loader.experiment != nil, "Successful paths should be cached")
        await loader.load(from: goal, to: start)
        expect(calls == 11, "Reversed connections must reuse cached polylines")
        expect(CampusLabExperiment.routeCost(loader.experiment!.dijkstra) == CampusLabExperiment.routeCost(first.dijkstra), "Reversed journey cost")
        print("PASS cache and reversed endpoint selection")

        await loader.load(from: .start, to: .defaultDestination, closedPathID: "gardens-house")
        let closed = try require(loader.experiment)
        expect(!closed.graph.edges.contains { $0.id == "gardens-house" }, "Closure must remove the search edge")
        expect(closed.closedPath?.id == "gardens-house" && !closed.previousEdges.isEmpty, "Closure retains segmented baseline ghost")
        print("PASS closure and prior route segments")

        await loader.load(from: start, to: start)
        expect(loader.experiment == nil && loader.errorMessage != nil && !loader.isLoading, "Same pin must recover without a crash")
        await loader.load(from: .init(id: "outside", name: "Outside", coordinate: .init(latitude: 0, longitude: 0)), to: goal)
        expect(loader.experiment == nil && loader.errorMessage != nil, "Out-of-campus selection must fail safely")
        print("PASS same-point and campus bounds")

        let offline = CampusRouteLoader { _, _ in throw Failure.offline }
        await offline.load(from: .start, to: .defaultDestination)
        expect(offline.experiment == nil && offline.errorMessage != nil, "Offline errors cannot fabricate a straight route")
        print("PASS unavailable provider has no fabricated route")

        var timeoutCalls = 0
        let timeout = CampusRouteLoader { _, _ in
            timeoutCalls += 1
            throw URLError(.timedOut)
        }
        await timeout.load(from: .start, to: .defaultDestination)
        expect(timeoutCalls == 1, "Timeout must stop instead of serially timing out every connection")
        expect(timeout.experiment == nil && timeout.errorMessage?.contains("too long") == true && !timeout.isLoading,
            "Timeout must leave a recoverable idle state")
        print("PASS provider timeout fails fast")

        var continuation: CheckedContinuation<[Coordinate], Error>?
        var delayedPair: (Coordinate, Coordinate)?
        var delayed = true
        let stale = CampusRouteLoader { from, to in
            if delayed {
                delayed = false
                delayedPair = (from, to)
                return try await withCheckedThrowingContinuation { continuation = $0 }
            }
            return [from, to]
        }
        let old = Task { await stale.load(from: .start, to: .defaultDestination) }
        while continuation == nil { await Task.yield() }
        await stale.load(from: goal, to: start)
        continuation?.resume(returning: [delayedPair!.0, delayedPair!.1])
        await old.value
        expect(stale.experiment?.routeTitle == "My destination → My start", "Late response must not overwrite newer selection")
        expect(!stale.isLoading && stale.errorMessage == nil, "Old request must not alter latest loading/error state")
        print("PASS stale request generation protection")

        var cancelContinuation: CheckedContinuation<[Coordinate], Error>?
        var cancelledPair: (Coordinate, Coordinate)?
        let cancelled = CampusRouteLoader { from, to in
            cancelledPair = (from, to)
            return try await withCheckedThrowingContinuation { cancelContinuation = $0 }
        }
        let task = Task { await cancelled.load(from: .start, to: .defaultDestination) }
        while cancelContinuation == nil { await Task.yield() }
        cancelled.cancel()
        cancelContinuation?.resume(returning: [cancelledPair!.0, cancelledPair!.1])
        await task.value
        expect(cancelled.experiment == nil && !cancelled.isLoading && cancelled.errorMessage == nil, "Cancelled request cannot publish")
        print("PASS explicit cancellation")

        var anchoredCalls = 0
        let anchored = CampusRouteLoader { from, to in
            anchoredCalls += 1
            // Only the first request chooses new nearby entrances. Every following
            // request must receive those established walking coordinates.
            if anchoredCalls == 1 {
                return [.init(latitude: from.latitude + 0.0001, longitude: from.longitude),
                        .init(latitude: to.latitude + 0.0001, longitude: to.longitude)]
            }
            return [from, to]
        }
        await anchored.load(from: .start, to: .defaultDestination)
        let snapped = try require(anchored.experiment)
        expect(snapped.maxSnapDistanceMetres > 10, "Selected pin gap must remain visible in metadata")
        let a = snapped.graph.edges.first { $0.id == "jms-gardens" }!.polyline.last!
        let b = snapped.graph.edges.first { $0.id == "gardens-house" }!.polyline.first!
        expect(a == b, "Incident paths must use a shared walking entrance")
        print("PASS shared entrance anchors and explicit pin gaps")
        print("9/9 campus routing checks passed")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure.offline }
        return value
    }
}
