import AlgorithmArenaCore
import SwiftUI

struct SearchStateSection<Footer: View>: View {
    let presentation: SearchPresentation
    var selectable: [NodeID] = []
    var selection: NodeID?
    var highlightedEdge: (from: NodeID, to: NodeID)?
    var onSelect: (NodeID) -> Void = { _ in }
    @ViewBuilder var footer: Footer

    @AppStorage("prefersNodeTable") private var prefersTable = false

    var body: some View {
        Section {
            Picker("View", selection: $prefersTable) {
                Text("Graph").tag(false)
                Text("Table").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if prefersTable {
                NodeTable(presentation: presentation)
            } else {
                SearchGraphView(
                    presentation: presentation,
                    selectable: selectable,
                    selection: selection,
                    highlightedEdge: highlightedEdge,
                    onSelect: onSelect
                )
            }
        } footer: {
            footer
        }
    }
}

extension SearchStateSection where Footer == EmptyView {
    init(presentation: SearchPresentation) {
        self.presentation = presentation
        self.footer = EmptyView()
    }
}
