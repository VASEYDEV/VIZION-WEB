import SwiftUI

/// Transient confirmations with an optional single action (Undo). Sits above
/// the FAB so a confirmation is never hidden behind the compose button.
@MainActor
@Observable
final class ToastCenter {
  struct Toast: Identifiable, Equatable {
    enum Tone { case neutral, error, success }
    let id = UUID()
    var text: String
    var tone: Tone = .neutral
    var actionLabel: String?
    var action: (@MainActor () -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
  }

  private(set) var current: Toast?
  private var dismissTask: Task<Void, Never>?

  /// Six seconds — the Undo window; an action keeps the toast a little longer.
  func show(_ text: String, tone: Toast.Tone = .neutral, actionLabel: String? = nil, action: (@MainActor () -> Void)? = nil) {
    dismissTask?.cancel()
    current = Toast(text: text, tone: tone, actionLabel: actionLabel, action: action)
    let id = current?.id
    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(action == nil ? 4 : 6))
      guard !Task.isCancelled, self?.current?.id == id else { return }
      self?.current = nil
    }
  }

  func error(_ text: String) { show(text, tone: .error) }

  func dismiss() {
    dismissTask?.cancel()
    current = nil
  }
}

struct ToastOverlay: View {
  @Environment(ToastCenter.self) private var center

  var body: some View {
    VStack {
      Spacer()
      if let toast = center.current {
        HStack(spacing: 12) {
          Text(toast.text)
            .font(.vzBody(14))
            .foregroundStyle(toast.tone == .error ? VZ.flare : VZ.text)
            .frame(maxWidth: .infinity, alignment: .leading)
          if let label = toast.actionLabel {
            Button(label) {
              toast.action?()
              center.dismiss()
            }
            .font(.vzBody(14, .semibold))
            .foregroundStyle(VZ.accent)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .vzGlassSolid(cornerRadius: VZ.Radius.control)
        .padding(.horizontal, 16)
        .padding(.bottom, VZ.floatGap)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityAddTraits(.isStaticText)
        .onTapGesture { center.dismiss() }
      }
    }
    .animation(VZ.Motion.slideAnimation, value: center.current)
    .allowsHitTesting(center.current != nil)
  }
}
