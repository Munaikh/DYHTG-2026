import AlgorithmArenaCore
import SwiftUI

struct LessonSessionView: View {
    let algorithm: AlgorithmKind
    let progress: LearnProgressStore
    let onNextLesson: (AlgorithmKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var lesson: PublicLesson?
    @State private var selectedOption: String?

    init(algorithm: AlgorithmKind, progress: LearnProgressStore, onNextLesson: @escaping (AlgorithmKind) -> Void) {
        self.algorithm = algorithm
        self.progress = progress
        self.onNextLesson = onNextLesson
        _lesson = State(initialValue: try? LessonCatalog.lesson(for: algorithm))
    }

    private var record: LessonProgress { progress.progress(for: algorithm) }
    private var questionIndex: Int { record.phase == 3 ? 2 : min(record.phase, 1) }

    var body: some View {
        Group {
            if let lesson {
                lessonContent(lesson)
            } else {
                ContentUnavailableView {
                    Label("Lesson couldn't open", systemImage: "arrow.clockwise")
                } description: {
                    Text("Your progress is safe. Try opening the lesson again.")
                } actions: {
                    Button("Try again") { self.lesson = try? LessonCatalog.lesson(for: algorithm) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(algorithm == .dijkstra ? "Dijkstra" : "A*")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Restart lesson", systemImage: "arrow.counterclockwise") {
                    selectedOption = nil
                    progress.restart(algorithm)
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("learn.restart")
            }
        }
    }

    private func lessonContent(_ lesson: PublicLesson) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 0).id("lesson-top")
                    if record.isComplete {
                        completion(lesson)
                    } else {
                        lessonProgress
                        if record.phase == 2 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("See every decision.")
                                    .font(.system(.title, design: .rounded, weight: .bold))
                                Text("Play the search, or move one step at a time.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            LessonTraceView(lesson: lesson)
                        } else {
                            let question = lesson.questions[questionIndex]
                            LessonQuestionView(
                                question: question, algorithm: algorithm, rule: lesson.rule,
                                selectedOption: $selectedOption,
                                submittedOption: record.answers[question.id]
                            )
                            .id(question.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .onChange(of: record.phase) { _, _ in
                selectedOption = nil
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo("lesson-top", anchor: .top)
                }
            }
            .task(id: feedbackScrollTarget(lesson)) {
                guard let target = feedbackScrollTarget(lesson) else { return }
                // Let the graph reveal its new state before moving to the explanation.
                // A new phase or restart cancels this task and prevents a stale jump.
                if reduceMotion {
                    await Task.yield()
                } else {
                    do { try await Task.sleep(for: .milliseconds(350)) }
                    catch { return }
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                lessonAction(lesson)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
            }
        }
    }

    private func feedbackScrollTarget(_ lesson: PublicLesson) -> String? {
        guard !record.isComplete, record.phase != 2 else { return nil }
        let question = lesson.questions[questionIndex]
        guard record.answers[question.id] != nil else { return nil }
        return "learn-feedback-\(question.id)"
    }

    private var lessonProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(["PREDICT", "CONNECT THE DOTS", "WATCH IT WORK", "YOUR TURN"][min(record.phase, 3)])
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(LearnStyle.teal)
                Spacer()
                Text("\(record.phase + 1) / 4")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                ForEach(0..<4) { phase in
                    Capsule()
                        .fill(phase <= record.phase ? LearnStyle.teal : Color(.quaternaryLabel))
                        .frame(height: 4)
                }
            }
            .accessibilityLabel("Step \(record.phase + 1) of 4")
        }
    }

    @ViewBuilder
    private func lessonAction(_ lesson: PublicLesson) -> some View {
        if record.isComplete {
            Button {
                if algorithm == .dijkstra {
                    onNextLesson(.aStar)
                } else {
                    dismiss()
                }
            } label: {
                Label(algorithm == .dijkstra ? "Next up: A*" : "Back to learning", systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(ArenaActionStyle())
            .accessibilityIdentifier("learn.finish")
        } else if record.phase == 2 {
            primaryAction("Try a new graph", identifier: "learn.next") {
                progress.advance(algorithm)
            }
        } else {
            let question = lesson.questions[questionIndex]
            if record.answers[question.id] != nil {
                primaryAction(record.phase == 3 ? "Finish lesson" : record.phase == 1 ? "Watch it work" : "Keep going", identifier: "learn.next") {
                    progress.advance(algorithm)
                }
            } else {
                primaryAction("Reveal the answer", identifier: "learn.reveal") {
                    guard let selectedOption else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        progress.answer(selectedOption, questionID: question.id, algorithm: algorithm)
                    }
                }
                .disabled(selectedOption == nil)
            }
        }
    }

    private func primaryAction(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(ArenaActionStyle())
        .accessibilityIdentifier(identifier)
    }

    private func completion(_ lesson: PublicLesson) -> some View {
        let correct = lesson.questions.filter { record.answers[$0.id] == $0.correctOptionID }.count
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(LearnStyle.mint)
                    .accessibilityHidden(true)
                Text("You made\nit click.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(lesson.title), explored.")
                    .font(.headline)
                    .foregroundStyle(LearnStyle.mint)
                Text("\(correct) of 3 predictions right first time. Every reveal builds your understanding.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LearnStyle.ink, in: RoundedRectangle(cornerRadius: 28))
            VStack(alignment: .leading, spacing: 12) {
                Label("Take this with you", systemImage: "lightbulb")
                    .font(.headline)
                Text(lesson.recap)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .learnCard()
            VStack(alignment: .leading, spacing: 12) {
                Text("Your final route")
                    .font(.headline)
                LessonCompletedGraph(lesson: lesson)
            }
            .learnCard()
            Button("Try the lesson again", systemImage: "arrow.counterclockwise") {
                selectedOption = nil
                progress.restart(algorithm)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

private struct LessonCompletedGraph: View {
    let lesson: PublicLesson

    private var presentation: SearchPresentation? {
        guard let last = lesson.trace.steps.last else { return nil }
        var value = SearchPresentation(scenario: lesson.scenario, algorithm: lesson.algorithm, state: last.state)
        if case .route(let nodes, _) = lesson.trace.outcome { value.routeNodes = nodes }
        return value
    }

    var body: some View {
        if let presentation { SearchGraphView(presentation: presentation) }
        if case .route(let nodes, let cost) = lesson.trace.outcome {
            Text("\(nodes.map(\.rawValue).joined(separator: " → ")) · cost \(cost)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LearnStyle.teal)
        }
    }
}
