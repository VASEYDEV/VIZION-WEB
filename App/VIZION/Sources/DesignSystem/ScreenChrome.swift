import SwiftUI

/// Full-bleed glass header (web: `ScreenHeader`): the brand lockup on the
/// primary screen, a plain display-face title elsewhere. Sub-level screens
/// get the system back chevron from NavigationStack.
struct ScreenHeader<Action: View>: View {
  var title: String?
  var brand = false
  @ViewBuilder var action: Action

  nonisolated init(title: String? = nil, brand: Bool = false, @ViewBuilder action: () -> Action) {
    self.title = title
    self.brand = brand
    self.action = action()
  }

  var body: some View {
    HStack(spacing: 12) {
      if brand {
        BrandLockup().accessibilityAddTraits(.isHeader)
      } else if let title {
        Text(title)
          .font(.vzDisplay(22, relativeTo: .title2))
          .tracking(0.8)
          .foregroundStyle(VZ.text)
          .lineLimit(1)
          .accessibilityAddTraits(.isHeader)
      }
      Spacer(minLength: 0)
      action
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(ChromeBar())
  }
}

extension ScreenHeader where Action == EmptyView {
  nonisolated init(title: String? = nil, brand: Bool = false) {
    self.init(title: title, brand: brand) { EmptyView() }
  }
}

/// Translucent bar fill for the header and tab bar (web: `.glass-chrome`).
struct ChromeBar: View {
  var body: some View {
    #if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        Rectangle().fill(.clear).glassEffect(.regular.tint(VZ.chrome), in: Rectangle())
          .overlay(alignment: .bottom) { Rectangle().fill(VZ.hair).frame(height: 1) }
      } else {
        legacy
      }
    #else
      legacy
    #endif
  }

  private var legacy: some View {
    Rectangle().fill(.ultraThinMaterial).overlay(Rectangle().fill(VZ.chrome))
      .overlay(alignment: .bottom) { Rectangle().fill(VZ.hair).frame(height: 1) }
  }
}

/// Every screen's scroll column: capped at the web's `max-w-screen-sm`.
struct ScreenColumn<Content: View>: View {
  var spacing: CGFloat = 24
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) { content }
      .frame(maxWidth: VZ.columnMaxWidth)
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity)
  }
}

/// Section heading in the rails' tracked micro-caps with an optional glyph.
struct SectionCaption: View {
  var text: String
  var icon: VZIcon?

  var body: some View {
    HStack(spacing: 6) {
      if let icon {
        IconView(icon, size: 14, strokeWidth: 2)
      }
      Text(text)
    }
    .vzCaps()
  }
}

extension View {
  /// Sheet chrome shared by every bottom sheet.
  func vzSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
    presentationDetents(detents)
      .presentationDragIndicator(.visible)
      .presentationBackground(VZ.ground)
      .presentationCornerRadius(VZ.Radius.panel + 4)
  }

  /// Applies the brand's field styling to text inputs.
  func vzInputFont() -> some View {
    font(.vzBody(16)).foregroundStyle(VZ.text).tint(VZ.accent)
  }
}
