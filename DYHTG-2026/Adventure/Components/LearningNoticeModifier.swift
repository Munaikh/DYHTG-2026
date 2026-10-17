import SwiftUI

struct LearningNoticeModifier: ViewModifier {
  @Bindable var learning: LearningStore
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        VStack(spacing: 8) {
          if let error = learning.storageError {
            VStack(alignment: .leading, spacing: 8) {
              Text(error).font(.subheadline)
              Button("Try loading again") { learning.reload() }
            }.padding(14).background(
              Color(uiColor: .secondarySystemGroupedBackground),
              in: RoundedRectangle(cornerRadius: 14)
            ).shadow(radius: 3)
          }
          if let notice = learning.notice {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "sparkles").font(.title2).accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 4) {
                Text(notice.title).font(.headline)
                Text(notice.detail).font(.subheadline)
              }
              Spacer(minLength: 0)
              Button {
                learning.notice = nil
              } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).frame(
                  minWidth: 44, minHeight: 44)
              }.accessibilityLabel("Dismiss reward notification")
            }.padding(16).foregroundStyle(.white).background(
              Color.arenaForest, in: RoundedRectangle(cornerRadius: 18)
            ).shadow(radius: 6)
              .accessibilityElement(children: .contain)
              .transition(
                systemReduceMotion || learning.profile.preferences.reduceMotion
                  ? .opacity : .move(edge: .top).combined(with: .opacity))
          }
        }.padding(16)
      }
      .animation(
        systemReduceMotion || learning.profile.preferences.reduceMotion
          ? nil : .easeInOut(duration: 0.25), value: learning.notice?.id
      )
      .task(id: learning.notice?.id) {
        guard let notice = learning.notice else { return }
        if UIAccessibility.isVoiceOverRunning {
          UIAccessibility.post(
            notification: .announcement, argument: "\(notice.title). \(notice.detail)")
        }
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        if learning.notice?.id == notice.id { learning.notice = nil }
      }
  }
}
