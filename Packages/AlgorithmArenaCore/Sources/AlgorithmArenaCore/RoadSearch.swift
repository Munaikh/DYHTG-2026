import Foundation

/// Geographic road graph, independent of MapKit. Distances are metres along actual OSM segments.
public struct RoadNetwork: Sendable {
    public struct Point: Sendable, Equatable {
        public let id: Int64
        public let latitude: Double
        public let longitude: Double
        public init(id: Int64, latitude: Double, longitude: Double) { self.id=id; self.latitude=latitude; self.longitude=longitude }
        public func distance(to other: Point) -> Double {
            let p = latitude * .pi/180, q = other.latitude * .pi/180
            let a = pow(sin((q-p)/2),2) + cos(p)*cos(q)*pow(sin((other.longitude-longitude) * .pi/360),2)
            return 6_371_000 * 2 * atan2(sqrt(max(0,min(1,a))),sqrt(max(0,1-a)))
        }
    }
    public struct Segment: Sendable {
        public let from: Int64; public let to: Int64; public let bidirectional: Bool
        public init(from: Int64, to: Int64, bidirectional: Bool = true) { self.from=from; self.to=to; self.bidirectional=bidirectional }
    }
    public let points: [Int64: Point]
    public let segments: [Segment]
    public init(points: [Point], segments: [Segment]) throws {
        guard !points.isEmpty, Set(points.map(\.id)).count == points.count,
            points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude)<=90 && abs($0.longitude)<=180 }) else { throw RoadSearchError.invalidNetwork }
        let indexed = Dictionary(uniqueKeysWithValues: points.map { ($0.id,$0) })
        guard segments.allSatisfy({ indexed[$0.from] != nil && indexed[$0.to] != nil }) else { throw RoadSearchError.invalidNetwork }
        self.points=indexed; self.segments=segments
    }
    public func nearest(to point: Point, maximumDistance: Double = 150) -> Point? {
        guard let nearest = points.values.min(by: { $0.distance(to: point) < $1.distance(to: point) }), nearest.distance(to: point)<=maximumDistance else { return nil }
        return nearest
    }
}
public enum RoadAlgorithm: String, CaseIterable, Sendable {
    case dijkstra = "Dijkstra", aStar = "A*", bfs = "BFS"
    public var explanation: String {
        switch self {
        case .dijkstra: "Finds the shortest distance on this non-negative road network."
        case .aStar: "Uses straight-line distance as an admissible lower bound to guide the search."
        case .bfs: "Finds the fewest graph edges. OSM segments vary in length, so this may be a longer walk."
        }
    }
}
public enum RoadSearchError: Error { case invalidNetwork, missingEndpoint, unreachable }
public struct RoadSearchResult: Sendable {
    public struct Visit: Sendable {
        public let node: Int64
        public let cost: Double
    }
    public let algorithm: RoadAlgorithm
    public let route: [Int64]
    public let visits: [Visit]
    public let distance: Double
    public var walkingSeconds: Double { distance/1.4 }
}
public enum RoadSearch {
    public static func run(_ network: RoadNetwork, from start: Int64, to goal: Int64, algorithm: RoadAlgorithm) throws -> RoadSearchResult {
        guard let destination=network.points[goal], network.points[start] != nil else { throw RoadSearchError.missingEndpoint }
        var adjacency: [Int64:[(Int64,Double)]] = [:]
        for segment in network.segments {
            let distance=network.points[segment.from]!.distance(to:network.points[segment.to]!)
            adjacency[segment.from,default:[]].append((segment.to,distance))
            if segment.bidirectional { adjacency[segment.to,default:[]].append((segment.from,distance)) }
        }
        for key in Array(adjacency.keys) { adjacency[key]?.sort { $0.0 < $1.0 } }
        var costs: [Int64:Double] = [start:0], previous: [Int64:Int64] = [:], settled = Set<Int64>()
        var visits: [RoadSearchResult.Visit] = [], queue = RoadHeap()
        func heuristic(_ id: Int64) -> Double { algorithm == .aStar ? network.points[id]!.distance(to:destination) : 0 }
        queue.push(.init(id:start,priority:heuristic(start)))
        while let current=queue.pop() {
            if settled.contains(current.id) { continue }
            settled.insert(current.id)
            visits.append(.init(node:current.id,cost:costs[current.id]!))
            if current.id == goal {
                var route=[goal]
                while let p=previous[route.last!] { route.append(p) }
                route.reverse()
                let distance=zip(route,route.dropFirst()).reduce(0.0) { $0+network.points[$1.0]!.distance(to:network.points[$1.1]!) }
                return .init(algorithm:algorithm,route:route,visits:visits,distance:distance)
            }
            for (next,distance) in adjacency[current.id,default:[]] where !settled.contains(next) {
                let candidate=costs[current.id]!+(algorithm == .bfs ? 1 : distance)
                if candidate < costs[next,default:.infinity] {
                    costs[next]=candidate; previous[next]=current.id
                    queue.push(.init(id:next,priority:candidate+heuristic(next)))
                }
            }
        }
        throw RoadSearchError.unreachable
    }
}
private struct RoadHeap {
    struct Entry { let id: Int64; let priority: Double }
    var entries: [Entry] = []
    func less(_ a: Entry,_ b: Entry) -> Bool { a.priority == b.priority ? a.id < b.id : a.priority < b.priority }
    mutating func push(_ entry: Entry) {
        entries.append(entry); var i=entries.count-1
        while i>0 { let parent=(i-1)/2; guard less(entries[i],entries[parent]) else { break }; entries.swapAt(i,parent); i=parent }
    }
    mutating func pop() -> Entry? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries.removeLast() }
        let first=entries[0]; entries[0]=entries.removeLast(); var i=0
        while true {
            let left=i*2+1; guard left<entries.count else { break }; let right=left+1
            let child=right<entries.count && less(entries[right],entries[left]) ? right : left
            guard less(entries[child],entries[i]) else { break }; entries.swapAt(i,child); i=child
        }
        return first
    }
}
