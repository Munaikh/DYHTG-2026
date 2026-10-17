import SwiftUI

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tabs = ["01 / Learn", "02 / Play", "03 / Visualize"]
    private let titles = ["Think like\nan algorithm.", "Then change\nthe game.", "See the search\nunfold."]
    private let subtitles = [
        "Explore five algorithms through short lessons and puzzles. Earn XP, complete quests, and make each step click.",
        "Challenge a friend in Plot Twist Duel. Three rounds. One bridge closure. Can you adapt?",
        "Choose two campus points. Watch a search follow real walking paths, then compare algorithms."
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ArenaEyebrow(text: tabs[page], color: LearnStyle.teal)
                    OnboardingDemo(page: page)
                        .frame(height: 250)
                        .foregroundStyle(.white)
                        .tint(ArenaPalette.mint)
                        .background(ArenaPalette.ink, in: .rect(cornerRadius: 28))
                    VStack(alignment: .leading, spacing: 14) {
                        Text(titles[page])
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitles[page])
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .id(page)
                    .transition(.opacity)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(ArenaPalette.canvas)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        ForEach(0..<3) { index in
                            Capsule().fill(index == page ? ArenaPalette.teal : Color.secondary.opacity(0.25))
                                .frame(width: index == page ? 28 : 8, height: 8)
                        }
                    }
                    .accessibilityLabel("Welcome screen \(page + 1) of 3")
                    ArenaGlassGroup {
                        HStack(spacing: 12) {
                            if page > 0 {
                                Button("Back") { move(-1) }
                                    .buttonStyle(ArenaActionStyle(prominent: false))
                                    .frame(maxWidth: 90)
                                    .accessibilityIdentifier("welcome.back")
                            }
                            Button(page == 2 ? "Let's get started" : "Continue") {
                                if page == 2 { completion() } else { move(1) }
                            }
                            .buttonStyle(ArenaActionStyle())
                            .accessibilityIdentifier("welcome.continue")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .arenaControlDock()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip", action: completion).accessibilityIdentifier("welcome.skip")
                }
            }
            .navigationTitle("Algorithm Arena")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(LearnStyle.teal)
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
                    let round = min(3, Int(cycle * 3) + 1)
                    Label(round == 2 ? "PLOT TWIST · BRIDGE CLOSED" : "ROUND \(round) OF 3", systemImage: round == 2 ? "bolt.fill" : "bolt.shield.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(round == 2 ? ArenaPalette.amber : ArenaPalette.mint)
                    ForEach(0..<2) { i in
                        let score = i == 0 ? round * 100 : (round == 1 ? 100 : (round - 1) * 100)
                        HStack(spacing: 14) {
                            Image(systemName: i == 0 ? "hare.fill" : "tortoise.fill")
                                .font(.title2)
                                .foregroundStyle(ArenaPalette.mint)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(i == 0 ? "Alex" : "Sam").font(.headline)
                                    Spacer()
                                    Text("\(score)").font(.headline.monospacedDigit())
                                        .contentTransition(.numericText())
                                }
                                ProgressView(value: Double(score), total: 300)
                                    .tint(ArenaPalette.mint)
                            }
                        }
                    }
                    Text("Predict privately. Reveal together.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.8))
                } else {
                    Canvas { ctx, size in
                        let points = [CGPoint(x: 0.12, y: 0.55), CGPoint(x: 0.32, y: 0.2), CGPoint(x: 0.36, y: 0.8), CGPoint(x: 0.6, y: 0.35), CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.9, y: 0.45)].map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        let edges = [(0,1),(0,2),(1,3),(2,3),(2,4),(3,5),(4,5)]
                        if page == 2 {
                            for i in 0..<7 {
                                var road = Path(); road.move(to: CGPoint(x: 0, y: CGFloat(i)*32)); road.addLine(to: CGPoint(x: size.width, y: CGFloat(i)*32+18))
                                ctx.stroke(road, with: .color(.white.opacity(0.08)), lineWidth: 8)
                            }
                        }
                        for (index, edge) in edges.enumerated() {
                            let a = points[edge.0], b = points[edge.1]
                            var line = Path(); line.move(to: a); line.addLine(to: b)
                            let guided = page == 2 && cycle >= 0.5
                            let phase = page == 2 ? cycle.truncatingRemainder(dividingBy: 0.5)*2 : cycle
                            let rank = guided ? [0,4,1,5,6,2,3][index] : index
                            let lit = Double(rank) / 8 < phase
                            ctx.stroke(line, with: .color(lit ? ArenaPalette.mint : .white.opacity(0.25)), style: StrokeStyle(lineWidth: lit ? 4 : 2, lineCap: .round))
                            if lit {
                                let t = (cycle * 3).truncatingRemainder(dividingBy: 1)
                                let p = CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)
                                ctx.fill(Path(ellipseIn: CGRect(x: p.x-3, y: p.y-3, width: 6, height: 6)), with: .color(.white))
                                if page == 2 {
                                    let reverse=CGPoint(x:b.x+(a.x-b.x)*t,y:b.y+(a.y-b.y)*t)
                                    ctx.fill(Path(ellipseIn:CGRect(x:reverse.x-3,y:reverse.y-3,width:6,height:6)),with:.color(ArenaPalette.amber))
                                }
                            }
                        }
                        if page == 2 {
                            if cycle.truncatingRemainder(dividingBy: 0.5)*2 > 0.65 {
                                var chosen=Path();chosen.move(to:points[0]);chosen.addLines([points[1],points[3],points[5]])
                                ctx.stroke(chosen,with:.color(ArenaPalette.mint),style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
                            }
                            ctx.draw(Text("Start").font(.caption.bold()),at:CGPoint(x:points[0].x,y:points[0].y+24))
                            ctx.draw(Text("Goal").font(.caption.bold()),at:CGPoint(x:points[5].x,y:points[5].y+24))
                        }
                        for (index, point) in points.enumerated() {
                            ctx.fill(Path(ellipseIn: CGRect(x: point.x-10,y: point.y-10,width: 20,height: 20)), with: .color(Double(index)/7 < cycle ? ArenaPalette.mint : .white.opacity(0.4)))
                        }
                    }.frame(height: 180)
                    Text(page == 0 ? "Predict  ·  Reveal  ·  Understand" : (cycle < 0.5 ? "Explore the network" : "Discover a route"))
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }.padding(24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page == 0 ? "An algorithm discovers a path through connected nodes" : page == 1 ? "A sample Plot Twist Duel: three rounds, a bridge closure, and shared scores" : "An illustrated search discovers a route from start to goal")
    }
}
