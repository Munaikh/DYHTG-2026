import AlgorithmArenaCore
import SwiftUI

struct AnswerSections: View {
    let challenge: ChallengeDefinition
    @Binding var draft: ChallengeDraft
    @FocusState.Binding var costFocused: Bool

    var body: some View {
        switch challenge.action {
        case .selectNode(let options):
            Section("Your Answer") {
                ForEach(options, id: \.self) { id in
                    ChoiceRow(title: "Node \(challenge.label(id))", isSelected: draft.node == id) {
                        draft.node = id
                    }
                }
            }
        case .enterCost(let id):
            Section {
                LabeledContent("g(\(challenge.label(id)))") {
                    TextField("Cost", text: $draft.cost)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($costFocused)
                        .onChange(of: draft.cost) {
                            let digits = draft.cost.filter(\.isNumber)
                            if digits != draft.cost { draft.cost = digits }
                        }
                }
            } header: {
                Text("Your Answer")
            } footer: {
                Text("Enter a whole number.")
            }
        case .selectRoute(let options):
            Section("Your Answer") {
                ForEach(options) { option in
                    ChoiceRow(title: option.text, isSelected: draft.routeOptionID == option.id) {
                        draft.routeOptionID = option.id
                    }
                }
            }
        case .transfer(let nodes, let reasons):
            Section("Next Node") {
                ForEach(nodes, id: \.self) { id in
                    ChoiceRow(title: "Node \(challenge.label(id))", isSelected: draft.node == id) {
                        draft.node = id
                    }
                }
            }
            Section("Reason") {
                ForEach(reasons) { reason in
                    ChoiceRow(title: reason.text, isSelected: draft.reasonID == reason.id) {
                        draft.reasonID = reason.id
                    }
                }
            }
        }
    }
}

private struct ChoiceRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
