import SwiftUI

struct BattleChallengeView: View {
    let challenge: BattleChallenge
    let busy: Bool
    var replay: [Int]? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let submit: ([Int]) -> Void
    @State private var selected: [Int] = []
    @State private var values: [Int] = []
    @State private var swapIndex: Int?

    var body: some View {
        Section {
            Text(challenge.title).font(.headline)
            Text(challenge.rule).font(.subheadline).foregroundStyle(.secondary)
            if !challenge.nodes.isEmpty {
                GeometryReader { outer in
                    ScrollView(.horizontal) {
                        graph.frame(width: max(outer.size.width, CGFloat(challenge.nodes.count/2)*58), height: 250)
                    }
                }.frame(height: 250)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46))], spacing: 12) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        Button {
                            if challenge.kind == "sort" {
                                if let first = swapIndex {
                                    values.swapAt(first, index); swapIndex = nil
                                } else { swapIndex = index }
                            } else { selected.append(value) }
                        } label: {
                            Text("\(value)").font(.headline.monospacedDigit()).frame(minWidth: 40, minHeight: 44)
                                .background(swapIndex == index || selected.contains(value) ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(replay != nil)
                        .accessibilityLabel(challenge.kind == "sort" ? "Value \(value), position \(index + 1). Select two to swap." : "Search value \(value)")
                    }
                }.padding(.vertical)
            }
            if !selected.isEmpty { Text(selected.map(String.init).joined(separator: " → ")).font(.caption.monospaced()).accessibilityLabel("Your steps: \(selected.map(String.init).joined(separator: ", "))") }
            if replay == nil {
            HStack {
                Button("Undo") { if !selected.isEmpty { selected.removeLast() } }.disabled(selected.isEmpty)
                Spacer()
                Button("Reset") { reset() }
            }
            PrimaryButton(title: "Submit Solution", isBusy: busy) {
                submit(challenge.kind == "sort" ? values : selected)
            }.disabled(busy || (challenge.kind != "sort" && selected.isEmpty))
            }
        } header: { Text(replay != nil ? "Solution Replay" : "Round \(challenge.round) · \(challenge.difficulty)") }
        .task {
            reset()
            guard let replay else { return }
            if challenge.kind == "sort" { values = replay; return }
            for node in replay {
                guard !Task.isCancelled else { return }
                selected.append(node)
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
    }
    private var graph: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    for edge in challenge.edges {
                        guard let a = challenge.nodes.first(where: { $0.id == edge.a }), let b = challenge.nodes.first(where: { $0.id == edge.b }) else { continue }
                        let p = CGPoint(x: a.x*size.width,y:a.y*size.height), q = CGPoint(x:b.x*size.width,y:b.y*size.height)
                        var line = Path(); line.move(to:p);line.addLine(to:q)
                        let active = zip(selected, selected.dropFirst()).contains { ($0 == edge.a && $1 == edge.b) || ($0 == edge.b && $1 == edge.a) }
                        ctx.stroke(line, with:.color(active ? .accentColor : .secondary.opacity(0.4)),lineWidth:active ? 4 : 2)
                        ctx.draw(Text("\(edge.weight)").font(.caption.bold()).foregroundStyle(Color.primary),at:CGPoint(x:(p.x+q.x)/2,y:(p.y+q.y)/2-12))
                    }
                }.accessibilityHidden(true)
                ForEach(challenge.nodes) { node in
                    Button { selected.append(node.id) } label: {
                        Text("\(node.id)").font(.body.bold().monospacedDigit()).frame(width:44,height:44)
                            .background(selected.contains(node.id) ? Color.accentColor : Color(.secondarySystemGroupedBackground),in:Circle())
                            .foregroundStyle(selected.contains(node.id) ? Color.white : Color.primary)
                            .overlay(Circle().stroke(Color.accentColor,lineWidth:2))
                    }.buttonStyle(.plain).disabled(replay != nil)
                    .position(x:node.x*geo.size.width,y:node.y*geo.size.height)
                    .accessibilityLabel("Node \(node.id). " + challenge.edges.filter { $0.a == node.id || $0.b == node.id }.map { "Connected to \($0.a == node.id ? $0.b : $0.a), cost \($0.weight)" }.joined(separator: ". "))
                }
            }
        }
    }
    private func reset() { selected = []; values = challenge.values; swapIndex = nil }
}
