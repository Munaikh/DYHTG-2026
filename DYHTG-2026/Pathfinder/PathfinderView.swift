import AlgorithmArenaCore
import MapKit
import SwiftUI

struct PathfinderView: View {
    @Bindable var battles: BattleStore
    @State private var location=LocationProvider()
    @State private var start: RoadNetwork.Point?
    @State private var goal: RoadNetwork.Point?
    @State private var startName="Choose a starting place"
    @State private var goalName="Where would you like to go?"
    @State private var searchStart=false
    @State private var searchGoal=false
    @State private var network: RoadNetwork?
    @State private var comparisons:[RoadSearchResult]=[]
    @State private var algorithm=RoadAlgorithm.dijkstra
    @State private var camera: MapCameraPosition = .automatic
    @State private var frame=0
    @State private var playing=false
    @State private var speed=12.0
    @State private var loading=false
    @State private var error: String?
    @State private var friendRoute=false
    @State private var routeRequest=UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var result: RoadSearchResult? { comparisons.first { $0.algorithm == algorithm } }
    private var visibleVisits: [RoadSearchResult.Visit] { result.map { Array($0.visits.prefix(frame)) } ?? [] }
    private var complete: Bool { result.map { frame >= $0.visits.count } ?? false }

    var body: some View {
        List {
            Section {
                Button { searchStart=true } label: { Label(startName,systemImage:"mappin.circle") }
                Button("Use My Current Location",systemImage:"location") { currentLocation() }.disabled(loading)
                Button { searchGoal=true } label: { Label(goalName,systemImage:"flag.checkered") }
                if start != nil && goal != nil {
                    Button("Reverse Route",systemImage:"arrow.up.arrow.down") {
                        let old=start;start=goal;goal=old
                        let name=startName;startName=goalName;goalName=name
                        clear()
                    }
                }
                PrimaryButton(title:"Explore Walking Network",busyTitle:"Loading Roads…",isBusy:loading) { load() }
                    .disabled(start == nil || goal == nil || loading)
            } footer: { Text("Explore places within 3 km. Endpoints snap to a road node within 150 m; off-road connections are not claimed as routes. Search is provided by Apple Maps.") }
            Section {
                Picker("Algorithm",selection:$algorithm) {
                    ForEach(RoadAlgorithm.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text(algorithm.explanation).font(.subheadline).foregroundStyle(.secondary)
                Text(algorithm == .bfs ? "Objective: fewest graph edges" : "Objective: shortest distance").font(.caption.bold())
                map.frame(height:340).clipShape(RoundedRectangle(cornerRadius:12))
                if let result {
                    HStack {
                        Button(playing ? "Pause" : "Start Animation",systemImage:playing ? "pause.fill" : "play.fill") {
                            if complete { frame=0 }
                            if reduceMotion { frame=result.visits.count } else { playing.toggle() }
                        }
                        Spacer()
                        Button("Reset") { playing=false;frame=0 }
                    }
                    Slider(value:$speed,in:1...60,step:1) { Text("Animation Speed") }
                    Text("\(Int(speed)) nodes / second · \(min(frame,result.visits.count)) explored").font(.caption).foregroundStyle(.secondary)
                    if frame>800 { Text("Most recent 800 explored nodes shown on the map.").font(.caption).foregroundStyle(.secondary) }
                    if let visit=visibleVisits.last {
                        Text("Current \(algorithm == .bfs ? "depth" : "distance"): \(Int(visit.cost))\(algorithm == .bfs ? " edges" : " m")").font(.caption.monospacedDigit())
                    }
                    LabeledContent("Route Distance",value:String(format:"%.2f km",result.distance/1000))
                    LabeledContent("Estimated Walk",value:"\(max(1,Int(result.walkingSeconds/60))) min")
                    Text("\(result.route.count-1) graph edges · \(result.visits.count) nodes explored").font(.caption)
                }
            } footer: { Text("Blue dots show visited road nodes. The route appears after exploration. Results are optimal only within the downloaded network. Walking time assumes 1.4 m/s and excludes crossings, terrain and live closures. Map data © OpenStreetMap contributors (ODbL).") }
            if !comparisons.isEmpty {
                Section("Compare Algorithms") {
                    ForEach(comparisons,id:\.algorithm) { item in
                        VStack(alignment:.leading,spacing:4) {
                            Text(item.algorithm.rawValue).font(.headline)
                            Text(String(format:"%.2f km · %d edges · %d nodes explored",item.distance/1000,item.route.count-1,item.visits.count)).font(.caption.monospacedDigit())
                        }
                    }
                    Link("OpenStreetMap data and attribution",destination:URL(string:"https://www.openstreetmap.org/copyright")!)
                }
            }
            friendSection
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Pathfinder")
        .sheet(isPresented:$searchStart) { PlaceSearchView(title:"Starting Place") { item in setPlace(item,isStart:true) } }
        .sheet(isPresented:$searchGoal) { PlaceSearchView(title:"Destination") { item in setPlace(item,isStart:false) } }
        .onChange(of:scenePhase) { _,phase in
            if phase != .active { playing=false }
            if friendRoute, let sharing=battles.state?.sharing, !sharingIsActive(sharing) { clearFriendRoute() }
        }
        .onDisappear { playing=false }
        .onChange(of:algorithm) { playing=false;frame=0 }
        .onChange(of:battles.state?.sharing?.accepted) { _,value in if value != true { clearFriendRoute() } }
        .onChange(of:battles.state?.sharing?.expiresAt) { _,value in if value == nil { clearFriendRoute() } }
        .task(id:playing) {
            guard playing else { return }
            while !Task.isCancelled {
                if playing, let result {
                    frame=min(frame+1,result.visits.count)
                    if complete { playing=false }
                }
                try? await Task.sleep(for:.milliseconds(Int(1000/speed)))
            }
        }
        .task {
            await battles.recover()
            while !Task.isCancelled {
                await battles.refresh()
                if let sharing=battles.state?.sharing, !sharingIsActive(sharing) { clearFriendRoute() }
                try? await Task.sleep(for:.seconds(5))
            }
        }
    }
    private var map: some View {
        Map(position:$camera) {
            if let network {
                ForEach(Array(visibleVisits.suffix(800)),id:\.node) { visit in
                    if let point=network.points[visit.node] {
                        Annotation("Explored",coordinate:coordinate(point)) { Circle().fill(Color.accentColor.opacity(0.6)).frame(width:6,height:6) }.annotationTitles(.hidden)
                    }
                }
                if complete,let result {
                    MapPolyline(coordinates:result.route.compactMap { network.points[$0].map(coordinate) }).stroke(Color.accentColor,lineWidth:5)
                }
            }
            if let start { Marker(startName,systemImage:"figure.walk",coordinate:coordinate(start)).tint(.green) }
            if let goal { Marker(goalName,systemImage:"flag.checkered",coordinate:coordinate(goal)).tint(Color.accentColor) }
        }
        .mapStyle(.standard(pointsOfInterest:.excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .accessibilityLabel("Walking network. \(frame) nodes explored. \(complete ? "Route discovered." : "Route exploration ready.")")
    }
    @ViewBuilder private var friendSection: some View {
        Section {
            if let state=battles.state, state.opponent != nil, ["lobby","playing"].contains(state.phase) {
                if let sharing=state.sharing,sharingIsActive(sharing) {
                    if !sharing.accepted {
                        if sharing.requester == state.viewer {
                            Label("Waiting for your friend's consent",systemImage:"clock")
                        } else {
                            Text("\(state.opponent?.nickname ?? "Your friend") requests temporary location sharing. Both players can stop at any time.")
                            Button("Accept") { Task { await battles.act("acceptLocation") } }.disabled(battles.busy)
                            Button("Decline",role:.destructive) { Task { await battles.act("stopLocation") } }.disabled(battles.busy)
                        }
                    } else {
                        Label("Sharing approved · until \(BattleTime.date(sharing.expiresAt)?.formatted(date: .omitted, time: .shortened) ?? "expiry")",systemImage:"location.fill").foregroundStyle(.tint)
                        Text("A location is sent only when you tap Share My Position. This shares a single position, not continuous tracking.").font(.caption).foregroundStyle(.secondary)
                        Button("Share My Position") { sharePosition() }.disabled(loading || battles.busy)
                        if sharing.positions.count == 2 {
                            Button("Route to My Friend") { routeToFriend(sharing,state:state) }
                        } else { Text("Waiting for both shared positions.").font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Stop Sharing",role:.destructive) { Task { await battles.act("stopLocation");clearFriendRoute() } }.disabled(battles.busy)
                } else {
                    Button("Find My Friend",systemImage:"person.2.wave.2") { Task { await battles.act("requestLocation") } }.disabled(battles.busy)
                }
                if let message=battles.error { Text(message).font(.caption).foregroundStyle(.red) }
            } else {
                Text("Connect in a private friend battle room to request temporary location sharing.").foregroundStyle(.secondary)
            }
        } header: { Text("Find My Friend") } footer: { Text("Both players must consent. Positions are hidden until approval and removed on stop, match completion or expiry. Session duration: 10 minutes. Joining a room never shares your location.") }
    }
    private func coordinate(_ p:RoadNetwork.Point) -> CLLocationCoordinate2D { .init(latitude:p.latitude,longitude:p.longitude) }
    private func setPlace(_ item:MKMapItem,isStart:Bool) {
        let c=item.placemark.coordinate
        let p=RoadNetwork.Point(id:isStart ? -1 : -2,latitude:c.latitude,longitude:c.longitude)
        if isStart { start=p;startName=item.name ?? "Start" } else { goal=p;goalName=item.name ?? "Destination" }
        friendRoute=false;clear()
    }
    private func clear() { routeRequest=UUID(); playing=false;frame=0;network=nil;comparisons=[];error=nil }
    private func currentLocation() {
        loading=true
        Task {
            defer { loading=false }
            do {
                let fix=try await location.currentFix()
                guard abs(fix.capturedAt.timeIntervalSinceNow)<=30 else { throw LocationProvider.Failure.unavailable }
                start = .init(id:-1,latitude:fix.coordinate.latitude,longitude:fix.coordinate.longitude); startName="My Location";friendRoute=false;clear()
            } catch { self.error="Location is unavailable or permission was denied. You can enter a starting place manually." }
        }
    }
    private func load() {
        guard let start,let goal else { return }
        clear();loading=true
        let token=routeRequest
        Task {
            defer { loading=false }
            do {
                let graph=try await RoadProvider().load(from:start,to:goal)
                guard let a=graph.nearest(to:start),let b=graph.nearest(to:goal) else { throw RoadProvider.Failure.missingRoad }
                let calculated=try await Task.detached(priority:.userInitiated) {
                    try RoadAlgorithm.allCases.map { try RoadSearch.run(graph,from:a.id,to:b.id,algorithm:$0) }
                }.value
                guard token == routeRequest else { return }
                if friendRoute { guard let sharing=battles.state?.sharing,sharing.accepted,sharingIsActive(sharing) else { clearFriendRoute();return } }
                network=graph;comparisons=calculated;camera = .automatic
                if reduceMotion { frame=result?.visits.count ?? 0 }
            } catch is RoadSearchError { guard token == routeRequest else { return }; self.error=RoadProvider.Failure.noRoute.localizedDescription }
            catch { guard token == routeRequest else { return }; self.error=error.localizedDescription }
        }
    }
    private func sharePosition() {
        loading=true
        Task {
            defer { loading=false }
            do {
                let fix=try await location.currentFix()
                guard abs(fix.capturedAt.timeIntervalSinceNow)<=30, fix.horizontalAccuracyMetres<=150 else { throw LocationProvider.Failure.unavailable }
                await battles.act("position",fields:["latitude":.double(fix.coordinate.latitude),"longitude":.double(fix.coordinate.longitude)])
            } catch { self.error="Unable to get an accurate location. Check location permission and try again." }
        }
    }
    private func sharingIsActive(_ sharing:BattleSharing) -> Bool {
        (BattleTime.date(sharing.expiresAt) ?? .distantPast)>Date()
    }
    private func routeToFriend(_ sharing:BattleSharing,state:BattleState) {
        guard sharingIsActive(sharing),let own=sharing.positions[state.viewer.uuidString.lowercased()],let otherID=state.opponent?.id,let other=sharing.positions[otherID.uuidString.lowercased()] else { return }
        start = .init(id:-1,latitude:own.latitude,longitude:own.longitude);goal = .init(id:-2,latitude:other.latitude,longitude:other.longitude)
        startName="My Shared Position";goalName=state.opponent?.nickname ?? "Friend";friendRoute=true;load()
    }
    private func clearFriendRoute() {
        guard friendRoute else { return }
        start=nil;goal=nil;startName="Choose a starting place";goalName="Where would you like to go?";friendRoute=false;clear()
    }
}
