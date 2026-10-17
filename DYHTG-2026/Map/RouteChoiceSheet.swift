import AlgorithmArenaCore
import MapKit
import SwiftUI

struct RouteChoiceSheet: View {
    let course: CourseGraph
    let paths: WalkingPaths
    let choose: (RouteBranch) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: RouteBranch?
    @State private var isConfirming = false
    @State private var isLocking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Map(initialPosition: .automatic, interactionModes: []) {
                        ForEach(RouteBranch.allCases, id: \.self) { branch in
                            MapPolyline(coordinates: paths.path(for: branch, in: course))
                                .stroke(
                                    branch == selection ? Color.accent : .white.opacity(0.8),
                                    style: StrokeStyle(lineWidth: branch == selection ? 6 : 4, lineCap: .round, lineJoin: .round)
                                )
                            if let node = course.node(course.middleStop(for: branch)) {
                                if branch == .bonus {
                                    Marker(course.stopTitle(node.id), systemImage: "star.fill", coordinate: node.coordinate.location)
                                        .tint(branch == selection ? Color.accent : Color(.systemGray))
                                } else {
                                    Marker(course.stopTitle(node.id), monogram: Text("2"), coordinate: node.coordinate.location)
                                        .tint(branch == selection ? Color.accent : Color(.systemGray))
                                }
                            }
                        }
                    }
                    .mapStyle(.hybrid(pointsOfInterest: .excludingAll))
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .accessibilityHidden(true)
                }

                Section {
                    ForEach(RouteBranch.allCases, id: \.self) { branch in
                        if let route = course.route(branch) {
                            RouteOptionRow(
                                course: course,
                                route: route,
                                extraDistance: extraDistance(for: branch),
                                isSelected: selection == branch
                            ) {
                                selection = branch
                            }
                        }
                    }
                } header: {
                    Text("Next Stop")
                } footer: {
                    Text("Both routes rejoin before Checkpoint 3. The question at your next stop stays hidden until you lock in a route.")
                }
            }
            .navigationTitle("Choose Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .bottomActions {
                PrimaryButton(
                    title: selection.map { "Lock In \($0.title) Route" } ?? "Choose a Route",
                    busyTitle: "Locking In...",
                    isBusy: isLocking
                ) {
                    isConfirming = true
                }
                .disabled(selection == nil)
            }
            .confirmationDialog(
                "Lock in the \(selection?.title.lowercased() ?? "") route?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Lock In") { lockIn() }
            } message: {
                Text("You can't change your route after this.")
            }
        }
        .interactiveDismissDisabled(isLocking)
    }

    private func extraDistance(for branch: RouteBranch) -> Int? {
        guard branch == .bonus, let bonus = course.route(.bonus), let standard = course.route(.standard) else { return nil }
        return bonus.distanceMetres - standard.distanceMetres
    }

    private func lockIn() {
        guard let selection, !isLocking else { return }
        isLocking = true
        Task {
            await choose(selection)
            isLocking = false
            dismiss()
        }
    }
}

private struct RouteOptionRow: View {
    let course: CourseGraph
    let route: CourseRoute
    let extraDistance: Int?
    let isSelected: Bool
    let select: () -> Void

    private var distance: String {
        Measurement(value: Double(route.distanceMetres), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(route.branch.title) · \(route.middleRewardPoints) points")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(course.placeName(course.middleStop(for: route.branch)))
                        .foregroundStyle(Color.primary)
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var details: String {
        var parts = ["\(distance) in total", route.difficulty]
        if let extraDistance, extraDistance > 0 {
            parts.insert("\(extraDistance) m further", at: 1)
        }
        return parts.joined(separator: " · ")
    }
}
