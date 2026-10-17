import SwiftUI

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let titles = ["Algorithms Come Alive.", "Think Faster. Win Smarter.", "Find Your Best Path."]
    private let subtitles = [
        "Discover how algorithms think, explore and solve problems through beautiful interactive experiences.",
        "Connect with friends, compete in algorithmic challenges, and climb your way to victory.",
        "Discover how algorithms navigate the real world and find the smartest routes between places and people."
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    OnboardingDemo(page: page)
                        .frame(height: 270)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    VStack(spacing: 16) {
                        Text(titles[page]).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(subtitles[page]).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: index == page ? 28 : 8, height: 8)
                        }
                    }
                    .accessibilityLabel("Welcome screen \(page + 1) of 3")
                    PrimaryButton(title: page == 2 ? "Let's Get Started" : "Continue") {
                        if page == 2 { completion() } else { move(1) }
                    }
                    if page > 0 { Button("Back") { move(-1) } }
                }
                .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Skip", action: completion) } }
        }
    }

    private func move(_ delta: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { page += delta }
    }
}

private struct OnboardingDemo: View {
    let page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { context in
            let cycle = reduceMotion ? 0.8 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
            VStack(spacing: 16) {
                if page == 1 {
                    Text(cycle > 0.85 ? "Alex wins!" : "Round \(Int(cycle * 3) + 1) · \(cycle < 0.5 ? "Easy" : "Hard")")
                        .font(.headline).foregroundStyle(.tint)
                    ForEach(0..<2) { i in
                        HStack {
                            Image(systemName: i == 0 ? "person.crop.circle.fill" : "person.crop.circle").font(.largeTitle)
                            VStack(alignment: .leading) {
                                HStack { Text(i == 0 ? "Alex" : "Sam"); Spacer(); Text("\(Int(min(1,cycle/0.85) * (i == 0 ? 100 : 76)))") }
                                ProgressView(value: min(1,cycle/0.85) * (i == 0 ? 1 : 0.76))
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        ForEach(0..<4) { i in
                            Text("\((cycle > 0.5 ? [1,2,3,4] : [3,1,4,2])[i])")
                                .font(.caption.bold().monospacedDigit()).frame(width: 28, height: 28)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                        }
                    }
                    Text("Tap nodes. Solve paths. Race to 100.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Canvas { ctx, size in
                        let points = [CGPoint(x: 0.12, y: 0.55), CGPoint(x: 0.32, y: 0.2), CGPoint(x: 0.36, y: 0.8), CGPoint(x: 0.6, y: 0.35), CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.9, y: 0.45)].map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        let edges = [(0,1),(0,2),(1,3),(2,3),(2,4),(3,5),(4,5)]
                        if page == 2 {
                            for i in 0..<7 {
                                var road = Path(); road.move(to: CGPoint(x: 0, y: CGFloat(i)*32)); road.addLine(to: CGPoint(x: size.width, y: CGFloat(i)*32+18))
                                ctx.stroke(road, with: .color(.secondary.opacity(0.12)), lineWidth: 8)
                            }
                        }
                        for (index, edge) in edges.enumerated() {
                            let a = points[edge.0], b = points[edge.1]
                            var line = Path(); line.move(to: a); line.addLine(to: b)
                            let guided = page == 2 && cycle >= 0.5
                            let phase = page == 2 ? cycle.truncatingRemainder(dividingBy: 0.5)*2 : cycle
                            let rank = guided ? [0,4,1,5,6,2,3][index] : index
                            let lit = Double(rank) / 8 < phase
                            ctx.stroke(line, with: .color(lit ? .accentColor : .secondary.opacity(0.2)), style: StrokeStyle(lineWidth: lit ? 4 : 2, lineCap: .round))
                            if lit {
                                let t = (cycle * 3).truncatingRemainder(dividingBy: 1)
                                let p = CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)
                                ctx.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)), with: .color(.primary))
                                if page == 2 {
                                    let reverse=CGPoint(x:b.x+(a.x-b.x)*t,y:b.y+(a.y-b.y)*t)
                                    ctx.fill(Path(ellipseIn:CGRect(x:reverse.x-3,y:reverse.y-3,width:6,height:6)),with:.color(.green))
                                }
                            }
                        }
                        if page == 2 {
                            if cycle.truncatingRemainder(dividingBy: 0.5)*2 > 0.65 {
                                var chosen=Path();chosen.move(to:points[0]);chosen.addLines([points[1],points[3],points[5]])
                                ctx.stroke(chosen,with:.color(.accentColor),style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
                            }
                            ctx.draw(Text("Alex").font(.caption.bold()),at:CGPoint(x:points[0].x,y:points[0].y+24))
                            ctx.draw(Text("Sam").font(.caption.bold()),at:CGPoint(x:points[5].x,y:points[5].y+24))
                        }
                        for (index, point) in points.enumerated() {
                            ctx.fill(Path(ellipseIn: CGRect(x: point.x-10,y: point.y-10,width: 20,height: 20)), with: .color(Double(index)/7 < cycle ? .accentColor : .secondary.opacity(0.4)))
                        }
                    }.frame(height: 180)
                    Text(page == 0 ? "Explore  ·  Discover  ·  Solve" : (cycle < 0.5 ? "BFS · Fictional sample locations" : "A* · Fictional sample locations"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page == 0 ? "An algorithm discovers a path through connected nodes" : page == 1 ? "Two sample players solve progressively harder challenges" : "Two fictional friends explore routes towards each other")
    }
}
