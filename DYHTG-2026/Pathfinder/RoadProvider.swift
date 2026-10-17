import AlgorithmArenaCore
import Foundation

/// Public OSM query, limited to a small pedestrian area. No synthetic route geometry.
struct RoadProvider {
    struct Response: Decodable {
        struct Element: Decodable {
            let type: String; let id: Int64; let lat: Double?; let lon: Double?
            let nodes: [Int64]?; let tags: [String:String]?
        }
        let elements: [Element]
        let remark: String?
    }
    enum Failure: LocalizedError {
        case tooFar, providerUnavailable, missingRoad, noRoute
        var errorDescription: String? {
            switch self {
            case .tooFar: "Choose places within 3 km of each other. Pathfinder explores a local walking network."
            case .providerUnavailable: "The OpenStreetMap road service is unavailable or busy. Please try again shortly."
            case .missingRoad: "No accessible walking network was found near one of these places. Try a nearby street or entrance."
            case .noRoute: "These places are not connected in the downloaded walking network. Try another entrance or nearby destination."
            }
        }
    }
    func load(from start: RoadNetwork.Point, to goal: RoadNetwork.Point) async throws -> RoadNetwork {
        guard start.distance(to: goal)<=3000 else { throw Failure.tooFar }
        let south=min(start.latitude,goal.latitude)-0.0045, north=max(start.latitude,goal.latitude)+0.0045
        let longitudeMargin=0.0045/max(0.15,cos(start.latitude * .pi/180))
        let west=min(start.longitude,goal.longitude)-longitudeMargin, east=max(start.longitude,goal.longitude)+longitudeMargin
        let query="[out:json][timeout:25];way[highway~\"^(footway|path|pedestrian|steps|living_street|residential|service|unclassified|tertiary|secondary)$\"][foot!~\"^(no|private)$\"][access!~\"^(no|private)$\"](\(south),\(west),\(north),\(east));(._;>;);out body;"
        var overpass=URLComponents(string:"https://overpass-api.de/api/interpreter")!
        overpass.queryItems=[URLQueryItem(name:"data",value:query)]
        var fallback=URLComponents(string:"https://api.openstreetmap.org/api/0.6/map.json")!
        fallback.queryItems=[URLQueryItem(name:"bbox",value:"\(west),\(south),\(east),\(north)")]
        let session=URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var decoded:Response?
        for endpoint in [overpass.url!,fallback.url!] {
            do {
                var request=URLRequest(url:endpoint);request.timeoutInterval=18
                request.setValue("application/json",forHTTPHeaderField:"Accept")
                request.setValue("AlgorithmArena/1.0 (educational walking-network visualisation)",forHTTPHeaderField:"User-Agent")
                let (data,response)=try await session.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,data.count<15_000_000 else { continue }
                let result=try JSONDecoder().decode(Response.self,from:data)
                guard result.remark == nil else { continue }
                decoded=result;break
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        guard let decoded else { throw Failure.providerUnavailable }
        let blocked=Set(decoded.elements.filter { $0.type == "node" && ($0.tags?["access"] == "no" || $0.tags?["access"] == "private" || ["fence","wall","gate","stile","turnstile"].contains($0.tags?["barrier"] ?? "")) }.map(\.id))
        let points=decoded.elements.compactMap { e -> RoadNetwork.Point? in
            guard e.type == "node",let lat=e.lat,let lon=e.lon else { return nil }
            return .init(id:e.id,latitude:lat,longitude:lon)
        }
        let known=Set(points.map(\.id))
        var segments:[RoadNetwork.Segment]=[]
        for way in decoded.elements where way.type == "way" {
            guard let nodes=way.nodes,let highway=way.tags?["highway"],
                ["footway","path","pedestrian","steps","living_street","residential","service","unclassified","tertiary","secondary"].contains(highway),
                !["no","private"].contains(way.tags?["foot"] ?? ""),
                !["no","private"].contains(way.tags?["access"] ?? ""),
                way.tags?["area"] != "yes" else { continue }
            let oneWay=way.tags?["oneway:foot"]
            for (a,b) in zip(nodes,nodes.dropFirst()) where known.contains(a) && known.contains(b) && !blocked.contains(a) && !blocked.contains(b) {
                segments.append(.init(from:oneWay == "-1" ? b : a,to:oneWay == "-1" ? a : b,bidirectional:oneWay != "yes" && oneWay != "-1"))
            }
        }
        let used=Set(segments.flatMap { [$0.from,$0.to] })
        guard used.count>1,used.count<30_000 else { throw Failure.missingRoad }
        return try RoadNetwork(points:points.filter { used.contains($0.id) },segments:segments)
    }
}
