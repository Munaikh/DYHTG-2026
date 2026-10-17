import AlgorithmArenaCore
import SwiftUI

struct CampusEndpointSheet: Identifiable {
    let role: SelectedEndpoint
    var id: String { role.rawValue }
}

/// Verified Apple place records are instant; typed searches resolve live campus POIs.
struct CampusEndpointPicker: View {
    let role: SelectedEndpoint
    let current: CampusMapPoint
    let choose: (CampusMapPoint) -> Void
    let chooseOnMap: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = CampusPlaceSearch()

    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matches: [CampusMapPoint] {
        if searchText.count >= 2 { return search.results }
        return CampusMapPoint.landmarks.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
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

                    ArenaEyebrow(text: searchText.count >= 2 ? "Apple Maps results" : "Campus places")
                    if search.isSearching {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching Apple Maps…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("visualize.placeSearch.loading")
                    }
                    if let error = search.errorMessage, searchText.count >= 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { Task { await search.search(searchText) } }
                                .buttonStyle(ArenaCompactButtonStyle())
                        }
                        .arenaCard()
                        .accessibilityIdentifier("visualize.placeSearch.error")
                    } else if matches.isEmpty && !search.isSearching {
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
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(point.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            if let address = point.address {
                                                Text(address).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
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
                    Label("Places from Apple Maps", systemImage: "map")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Place pins mark the building. Walking paths connect to its mapped entrance.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(ArenaPalette.canvas)
            .searchable(text: $query, prompt: "Search Apple Maps on campus")
            .task(id: searchText) {
                await search.search(searchText, debounce: .milliseconds(300))
            }
            .onDisappear { search.cancel() }
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
