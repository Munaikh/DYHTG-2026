import AlgorithmArenaCore
import SwiftUI

struct CampusEndpointSheet: Identifiable {
    let role: SelectedEndpoint
    var id: String { role.rawValue }
}

/// Campus landmarks are instant and work offline; map placement covers any other point.
struct CampusEndpointPicker: View {
    let role: SelectedEndpoint
    let current: CampusMapPoint
    let choose: (CampusMapPoint) -> Void
    let chooseOnMap: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [CampusMapPoint] {
        CampusMapPoint.landmarks.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        dismiss()
                        chooseOnMap()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title2)
                                .frame(width: 45, height: 45)
                                .background(ArenaPalette.mint.opacity(0.13), in: .rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Choose on the map").font(.headline)
                                Text("Drop a pin anywhere on campus.").font(.caption).foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                        }
                        .foregroundStyle(ArenaPalette.mint)
                        .padding(18)
                        .background(ArenaPalette.ink, in: .rect(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("visualize.chooseOnMap")

                    ArenaEyebrow(text: "Campus landmarks")
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(matches) { point in
                                Button {
                                    choose(point)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: "building.2")
                                            .font(.body)
                                            .foregroundStyle(LearnStyle.teal)
                                            .frame(width: 28)
                                        Text(point.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 6)
                                        if current.id == point.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(LearnStyle.teal)
                                        } else {
                                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 18)
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("visualize.landmark.\(point.id)")
                                if point.id != matches.last?.id { Divider().padding(.leading, 57) }
                            }
                        }
                        .background(ArenaPalette.surface, in: .rect(cornerRadius: 22))
                    }
                }
                .padding(20)
            }
            .background(ArenaPalette.canvas)
            .searchable(text: $query, prompt: "Find a campus landmark")
            .navigationTitle(role == .source ? "Choose your start" : "Choose destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("visualize.picker.cancel")
                }
            }
            .tint(LearnStyle.teal)
        }
    }
}
