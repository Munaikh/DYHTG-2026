import Testing
@testable import AlgorithmArenaCore

@Test func geographicSearchSeparatesHopsFromDistance() throws {
    // Two-edge detour versus a three-edge direct walk.
    let graph=try RoadNetwork(points:[
        .init(id:0,latitude:55,longitude:-4),
        .init(id:1,latitude:55.01,longitude:-4),
        .init(id:2,latitude:55,longitude:-3.999),
        .init(id:3,latitude:55,longitude:-3.998),
        .init(id:4,latitude:55,longitude:-3.997)
    ],segments:[.init(from:0,to:1),.init(from:1,to:4),.init(from:0,to:2),.init(from:2,to:3),.init(from:3,to:4)])
    let dijkstra=try RoadSearch.run(graph,from:0,to:4,algorithm:.dijkstra)
    let astar=try RoadSearch.run(graph,from:0,to:4,algorithm:.aStar)
    let bfs=try RoadSearch.run(graph,from:0,to:4,algorithm:.bfs)
    #expect(dijkstra.route == [0,2,3,4])
    #expect(abs(dijkstra.distance-astar.distance)<0.001)
    #expect(bfs.route == [0,1,4])
    #expect(bfs.distance>dijkstra.distance)
    #expect(astar.visits.count<=dijkstra.visits.count)
    #expect(graph.nearest(to:.init(id:-1,latitude:0,longitude:0)) == nil)
}
@Test func geographicSearchRespectsDirectionAndRejectsDisconnectedRoutes() throws {
    let points=[RoadNetwork.Point(id:0,latitude:55,longitude:-4),.init(id:1,latitude:55.001,longitude:-4),.init(id:2,latitude:56,longitude:-4)]
    let graph=try RoadNetwork(points:points,segments:[.init(from:0,to:1,bidirectional:false)])
    for algorithm in RoadAlgorithm.allCases {
        #expect(throws:RoadSearchError.unreachable) { try RoadSearch.run(graph,from:1,to:0,algorithm:algorithm) }
        #expect(throws:RoadSearchError.unreachable) { try RoadSearch.run(graph,from:0,to:2,algorithm:algorithm) }
        let same=try RoadSearch.run(graph,from:0,to:0,algorithm:algorithm)
        #expect(same.route == [0]); #expect(same.distance == 0)
    }
    #expect(throws:RoadSearchError.invalidNetwork) { try RoadNetwork(points:points,segments:[.init(from:0,to:99)]) }
}
