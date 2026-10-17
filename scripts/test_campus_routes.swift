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
        expect(first.places.contains { $0.id == first.scenario.source } && first.places.contains { $0.id == first.scenario.goal }, "Selected entrances must become graph vertices")
        for place in first.places where place.id != first.scenario.source && place.id != first.scenario.goal {
            let degree = first.graph.edges.filter { $0.from == place.id || $0.to == place.id }.count
            expect(degree >= 3, "Intermediate nodes must be path junctions, not bends or buildings")
        }
        expect(first.routeTitle == "My start → My destination", "Selected point names must survive")
        expect(first.scenario.source == "selected-source" && first.scenario.goal == "selected-goal", "Dynamic source and goal")
        expect(CampusLabExperiment.routeCost(first.dijkstra) == CampusLabExperiment.routeCost(first.aStar), "Both algorithms must find optimal equal cost")
        expect(calls == 12, "Direct walk, seven corridor samples, and four endpoint links")
        print("PASS arbitrary selected endpoints and exact search graph")

        await loader.load(from: start, to: goal)
        expect(calls == 12 && loader.experiment != nil, "Successful paths should be cached")
        await loader.load(from: goal, to: start)
        expect(calls == 12, "Reversed connections must reuse cached polylines")
        expect(CampusLabExperiment.routeCost(loader.experiment!.dijkstra) == CampusLabExperiment.routeCost(first.dijkstra), "Reversed journey cost")
        print("PASS cache and reversed endpoint selection")

        await loader.load(from: .start, to: .defaultDestination)
        let baseline = try require(loader.experiment)
        let closureID = try require(baseline.graph.edges.first?.id)
        await loader.load(from: .start, to: .defaultDestination, closedPathID: closureID)
        let closed = try require(loader.experiment)
        expect(!closed.graph.edges.contains { $0.id == closureID }, "Closure must remove the search edge")
        expect(closed.closedPath?.id == closureID && !closed.previousEdges.isEmpty, "Closure retains segmented baseline ghost")
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
        let entrance = try require(snapped.place(snapped.scenario.source))
        expect(entrance.coordinate == snapped.graph.source.coordinate, "Algorithm source must sit on the walking path")
        expect(entrance.coordinate != CampusMapPoint.start.coordinate, "POI position and walking entrance must remain distinct")
        expect(snapped.graph.edges.contains { $0.polyline.contains(entrance.coordinate) }, "Entrance must lie on returned geometry")
        print("PASS walking entrance anchors remain distinct from place pins")

        let revisedJMS = CampusMapPoint(id: CampusMapPoint.start.id, name: CampusMapPoint.start.name,
            coordinate: .init(latitude: CampusMapPoint.start.coordinate.latitude + 0.00002,
                longitude: CampusMapPoint.start.coordinate.longitude), address: "110 University Avenue", isAppleMapsPlace: true)
        await loader.load(from: revisedJMS, to: .defaultDestination)
        let revised = try require(loader.experiment)
        expect(revised.graph.source.coordinate == revisedJMS.coordinate, "Live place coordinates must replace the bundled location")
        expect(revised.scenario.source.rawValue == revisedJMS.id, "Known live place must preserve its identity")
        print("PASS live known POI refresh")

        expect(CampusPlaceSearch.normalizedQuery("  JMS  ") == "James McCune Smith Learning Hub", "JMS abbreviation should resolve to its Apple place name")
        let library = CampusMapPoint.defaultDestination
        let alias = CampusMapPoint(id: "unmatched", name: "University of Glasgow", coordinate: library.coordinate,
            address: "Hillhead Street", isAppleMapsPlace: true)
        let busStop = CampusMapPoint(id: "unmatched", name: "University Library Bus Stop", coordinate: library.coordinate, isAppleMapsPlace: true)
        let outside = CampusMapPoint(id: "unmatched", name: "University Library", coordinate: .init(latitude: 0, longitude: 0), isAppleMapsPlace: true)
        let matches = CampusPlaceSearch.canonicalResults([alias, alias, busStop, outside])
        expect(matches.count == 2 && matches.first?.id == library.id, "Known alias, deduplication and campus bounds")
        expect(matches.last?.id != library.id && matches.last?.name == busStop.name, "Nearby unrelated POIs must not acquire a building identity")
        expect(CampusPlaceSearch.canonicalResults([busStop]) == CampusPlaceSearch.canonicalResults([busStop]), "Extra place IDs remain stable")
        print("PASS POI aliases, campus bounds and distinct place identities")

        var searchCalls = 0
        let search = CampusPlaceSearch { query in
            searchCalls += 1
            expect(query == "James McCune Smith Learning Hub", "Provider receives normalized query")
            return [revisedJMS]
        }
        await search.search("j")
        expect(searchCalls == 0 && search.results.isEmpty && !search.isSearching, "Short queries don't call Apple")
        await search.search("JMS")
        expect(searchCalls == 1 && search.results.first?.coordinate == revisedJMS.coordinate && !search.isSearching, "Live coordinates must survive identity matching")
        print("PASS live place search lifecycle")

        var searchContinuation: CheckedContinuation<[CampusMapPoint], Error>?
        let latestSearch = CampusPlaceSearch { query in
            if query == "old" { return try await withCheckedThrowingContinuation { searchContinuation = $0 } }
            return [alias]
        }
        let oldSearch = Task { await latestSearch.search("old") }
        while searchContinuation == nil { await Task.yield() }
        await latestSearch.search("new")
        searchContinuation?.resume(returning: [revisedJMS])
        await oldSearch.value
        expect(latestSearch.results.first?.id == library.id && !latestSearch.isSearching, "Late query cannot replace current results")
        latestSearch.cancel()
        expect(latestSearch.results.isEmpty && latestSearch.errorMessage == nil, "Cancelled search clears stale results")
        print("PASS stale POI searches and cancellation")

        let failedSearch = CampusPlaceSearch { _ in throw URLError(.timedOut) }
        await failedSearch.search("JMS")
        expect(failedSearch.results.isEmpty && failedSearch.errorMessage?.contains("too long") == true && !failedSearch.isSearching, "Search timeout must recover without fake results")
        print("PASS recoverable POI search error")
        print("14/14 campus routing and place search checks passed")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure.offline }
        return value
    }
}
