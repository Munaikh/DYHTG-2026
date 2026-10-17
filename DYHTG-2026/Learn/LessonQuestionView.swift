import AlgorithmArenaCore
import SwiftUI

struct LessonQuestionView: View {
    let question: PublicLessonQuestion
    let algorithm: AlgorithmKind
    let rule: String
    @Binding var selectedOption: String?
    let submittedOption: String?

    @State private var showsHint = false
    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRevealed: Bool { submittedOption != nil }
    private var presentation: SearchPresentation {
        let step = isRevealed ? question.reveal : question.before
        var value = SearchPresentation(scenario: question.scenario, algorithm: algorithm, state: step.state)
        if isRevealed, case .expand(let nodeID) = step.event { value.current = nodeID }
        return value
    }
    private var highlightedEdge: (from: NodeID, to: NodeID)? {
        guard isRevealed, case .relax(let from, let to, _, _, _) = question.reveal.event else { return nil }
        return (from, to)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(question.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(question.prompt)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("S · start", systemImage: "location.circle")
                    Spacer()
                    Label("G · goal", systemImage: "flag.checkered")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                SearchGraphView(
                    presentation: presentation,
                    selectable: isRevealed ? [] : question.options.compactMap(\.nodeID),
                    selection: (submittedOption ?? selectedOption).flatMap { optionID in
                        question.options.first { $0.id == optionID }?.nodeID
                    },
                    highlightedEdge: highlightedEdge
                ) { nodeID in
                    selectedOption = nodeID.rawValue
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isRevealed)
                Text(algorithm == .dijkstra ? "g = cost so far · edge numbers = travel cost" : "g = so far · h = estimate left · f = g + h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Explore the node values") {
                    LessonNodeValues(presentation: presentation)
                        .padding(.top, 8)
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
            }
            .learnCard()

            if isRevealed {
                feedback
                    .id("learn-feedback-\(question.id)")
            } else {
                Text("Your prediction")
                    .font(.headline)
            }
            options
            if !isRevealed {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showsHint.toggle() }
                } label: {
                    Label(showsHint ? "Hide hint" : "Need a nudge?", systemImage: "lightbulb")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LearnStyle.teal)
                if showsHint {
                    Text(question.hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LearnStyle.mint.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if !isRevealed && question.id == "frontier" {
                Text(rule)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isRevealed) { _, revealed in
            if revealed { feedbackIsFocused = true }
        }
    }

    private var options: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(question.options) { option in
                    optionButton(option)
                }
            }
            VStack(spacing: 10) {
                ForEach(question.options) { option in
                    optionButton(option)
                }
            }
        }
    }

    private func optionButton(_ option: PublicLessonOption) -> some View {
        let chosen = (submittedOption ?? selectedOption) == option.id
        let isCorrect = isRevealed && question.isCorrect(option.id)
        let isWrong = isRevealed && chosen && !question.isCorrect(option.id)
        return Button {
            guard !isRevealed else { return }
            selectedOption = option.id
        } label: {
            HStack(spacing: 7) {
                Text(option.title)
                    .font(.headline)
                    .fixedSize()
                if isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                } else if isWrong {
                    Image(systemName: "xmark.circle")
                } else if chosen {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(chosen || isCorrect ? LearnStyle.teal : Color.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(chosen || isCorrect ? LearnStyle.mint.opacity(0.35) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(chosen || isCorrect ? LearnStyle.teal : Color(.separator).opacity(0.35), lineWidth: chosen || isCorrect ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isRevealed)
        .accessibilityLabel(option.title)
        .accessibilityValue(isCorrect ? "Correct answer" : isWrong ? "Your answer, not quite" : chosen ? "Selected" : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("learn.option.\(option.id)")
    }

    private var feedback: some View {
        let correct = submittedOption.map(question.isCorrect) ?? false
        return VStack(alignment: .leading, spacing: 10) {
            Label(correct ? "You've got it." : "A useful wrong turn.", systemImage: correct ? "checkmark.circle.fill" : "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(LearnStyle.teal)
            Text(question.explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LearnStyle.mint.opacity(0.25), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityFocused($feedbackIsFocused)
        .accessibilityIdentifier("learn.feedback")
    }
}

struct LessonNodeValues: View {
    let presentation: SearchPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(presentation.nodes) { node in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(node.label) · \(node.state.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(presentation.algorithm == .dijkstra
                         ? "g = \(node.g.map(String.init) ?? "unknown")"
                         : "g = \(node.g.map(String.init) ?? "unknown") · h = \(node.h) · f = \(node.f.map(String.init) ?? "unknown")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
