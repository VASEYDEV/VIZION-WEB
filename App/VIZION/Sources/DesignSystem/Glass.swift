import SwiftUI

/// Frosted Onyx glass — the "raised" elevation tier (web: `.glass`). Three
/// things make it read as glass rather than flat tint: the blur, the hairline,
/// and the top-edge sheen. On iOS 26+ the system Liquid Glass material carries
/// the blur; earlier systems use the thin material tinted with `VZ.glass`.
struct GlassPanel: ViewModifier {
  var cornerRadius: CGFloat = VZ.Radius.panel
  /// The opaque work-surface tier (`.glass-solid`) for text-dense panels.
  var solid = false

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    content
      .background { GlassBackground(shape: shape, solid: solid) }
      .overlay { shape.strokeBorder(VZ.hair, lineWidth: 1) }
      .overlay(alignment: .top) {
        Rectangle().fill(VZ.sheen).frame(height: 1).padding(.horizontal, cornerRadius / 2)
          .blendMode(.plusLighter)
      }
      .clipShape(shape)
  }
}

private struct GlassBackground<S: InsettableShape>: View {
  let shape: S
  let solid: Bool

  var body: some View {
    if solid {
      shape.fill(VZ.onyx)
    } else {
      #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
          shape.fill(Color.clear).glassEffect(.regular.tint(VZ.glass), in: shape)
        } else {
          legacy
        }
      #else
        legacy
      #endif
    }
  }

  private var legacy: some View {
    shape.fill(.ultraThinMaterial).overlay(shape.fill(VZ.glass))
  }
}

extension View {
  func vzGlass(cornerRadius: CGFloat = VZ.Radius.panel) -> some View {
    modifier(GlassPanel(cornerRadius: cornerRadius))
  }

  func vzGlassSolid(cornerRadius: CGFloat = VZ.Radius.panel) -> some View {
    modifier(GlassPanel(cornerRadius: cornerRadius, solid: true))
  }

  /// A fill-only wash for a caption sitting directly on the ambient layer
  /// (web: `.ambient-scrim`) — no hairline, no sheen.
  func vzScrim(cornerRadius: CGFloat = VZ.Radius.control) -> some View {
    background(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(VZ.ground.opacity(0.6))
    )
  }

  /// Glass input field styling (the sign-in fields, the composer editor).
  func vzField() -> some View {
    padding(.horizontal, 16).padding(.vertical, 12)
      .frame(minHeight: 48)
      .vzGlass(cornerRadius: VZ.Radius.control)
  }
}
