import SwiftUI

private enum ProfileTint: String, CaseIterable, Identifiable {
    case mint, amber, sky
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .mint: ArenaPalette.mint
        case .amber: ArenaPalette.amber
        case .sky: Color(red: 0.57, green: 0.79, blue: 1)
        }
    }
}

private struct PlayerAvatar: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var foreground: Color = ArenaPalette.ink

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(color, in: Circle())
    }
}

/// A single profile entry point reused by all three tabs.
struct ProfileButton: View {
    @AppStorage("battleAvatar") private var avatar = "person.crop.circle.fill"
    @AppStorage("profileTint") private var tint = ProfileTint.mint.rawValue
    @State private var showingProfile = false

    var body: some View {
        Button { showingProfile = true } label: {
            PlayerAvatar(symbol: avatar, color: (ProfileTint(rawValue: tint) ?? .mint).color, size: 32)
        }
        .accessibilityLabel("Edit profile")
        .accessibilityIdentifier("profile.open")
        .sheet(isPresented: $showingProfile) {
            NavigationStack { ProfileView() }
                .tint(ArenaPalette.teal)
        }
    }
}

struct ProfileView: View {
    @Environment(LearningStore.self) private var learning
    @AppStorage("nickname") private var nickname = ""
    @AppStorage("battleAvatar") private var avatar = "person.crop.circle.fill"
    @AppStorage("profileTint") private var tint = ProfileTint.mint.rawValue
    @State private var draftNickname = ""
    @State private var draftAvatar = "person.crop.circle.fill"
    @State private var draftTint = ProfileTint.mint
    @State private var loaded = false
    @State private var showingWelcome = false
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let avatars: [(symbol: String, name: String)] = [
        ("person.crop.circle.fill", "Player"), ("bolt.fill", "Bolt"),
        ("hare.fill", "Hare"), ("tortoise.fill", "Tortoise"),
        ("bird.fill", "Bird"), ("leaf.fill", "Leaf"),
        ("paperplane.fill", "Explorer"), ("star.fill", "Star")
    ]
    private var cleanNickname: String { draftNickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validNickname: Bool { (2...20).contains(cleanNickname.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                preview
                AdventureProfile(learning: learning)
                nameEditor
                avatarPicker
                colorPicker
                Button {
                    nameFocused = false
                    showingWelcome = true
                } label: {
                    Label("Watch the welcome tour", systemImage: "play.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("profile.welcome")
                Text("Your profile saves on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ArenaPalette.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Your profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("profile.cancel")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save profile", systemImage: "checkmark") { save() }
                .buttonStyle(ArenaActionStyle())
                .disabled(!validNickname)
                .accessibilityIdentifier("profile.save")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .onAppear {
            guard !loaded else { return }
            draftNickname = nickname
            draftAvatar = avatar
            draftTint = ProfileTint(rawValue: tint) ?? .mint
            loaded = true
        }
        .fullScreenCover(isPresented: $showingWelcome) {
            OnboardingView { showingWelcome = false }
        }
        .modifier(LearningNoticeModifier(learning: learning))
    }

    private var preview: some View {
        HStack(spacing: 18) {
            PlayerAvatar(symbol: draftAvatar, color: draftTint.color, size: 76)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 8) {
                ArenaEyebrow(text: "Your arena ID", color: draftTint.color)
                Text(cleanNickname.isEmpty ? "Your nickname" : cleanNickname)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(learning.equippedTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArenaPalette.ink, in: .rect(cornerRadius: 24))
    }

    private var nameEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ArenaEyebrow(text: "Duel name")
                Spacer()
                Text("\(cleanNickname.count)/20")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(validNickname ? Color.secondary : ArenaPalette.teal)
            }
            HStack {
                TextField("Your nickname", text: $draftNickname)
                    .font(.title3.weight(.semibold))
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
                    .accessibilityIdentifier("profile.nickname")
                    .onChange(of: draftNickname) { _, value in
                        if value.count > 20 { draftNickname = String(value.prefix(20)) }
                    }
                if !draftNickname.isEmpty {
                    Button("Clear nickname", systemImage: "xmark.circle.fill") { draftNickname = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.clearName")
                }
            }
            .padding(14)
            .background(ArenaPalette.canvas, in: .rect(cornerRadius: 14))
            Text(validNickname ? "Used when you create or join your next duel." : "Choose a nickname with 2–20 characters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .arenaCard()
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArenaEyebrow(text: "Pick your player")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                ForEach(avatars, id: \.symbol) { item in
                    let selected = draftAvatar == item.symbol
                    Button {
                        nameFocused = false
                        draftAvatar = item.symbol
                    } label: {
                        PlayerAvatar(
                            symbol: item.symbol,
                            color: selected ? draftTint.color : ArenaPalette.canvas,
                            size: 52,
                            foreground: !selected && colorScheme == .dark ? .white : ArenaPalette.ink
                        )
                            .padding(4)
                            .overlay(Circle().strokeBorder(draftAvatar == item.symbol ? ArenaPalette.teal : .clear, lineWidth: 2))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(draftAvatar == item.symbol ? .isSelected : [])
                    .accessibilityIdentifier("profile.avatar.\(item.name.lowercased())")
                }
            }
        }
        .arenaCard()
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArenaEyebrow(text: "Make it yours")
            HStack(spacing: 12) {
                ForEach(ProfileTint.allCases) { choice in
                    Button {
                        nameFocused = false
                        draftTint = choice
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .opacity(draftTint == choice ? 1 : 0)
                                .frame(width: 40, height: 40)
                                .background(choice.color, in: Circle())
                                .foregroundStyle(ArenaPalette.ink)
                            Text(choice.title).font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draftTint == choice ? .isSelected : [])
                    .accessibilityIdentifier("profile.tint.\(choice.rawValue)")
                }
            }
        }
        .arenaCard()
    }

    private func save() {
        guard validNickname else { return }
        nickname = cleanNickname
        avatar = draftAvatar
        tint = draftTint.rawValue
        learning.syncNickname()
        dismiss()
    }
}
