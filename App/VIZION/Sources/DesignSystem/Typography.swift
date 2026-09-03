import SwiftUI

/// The three locked type roles (web: `fonts/index.ts`), registered from
/// Resources/Fonts via UIAppFonts. PostScript names, not family names — the
/// vendored Reddit Sans weights ship as separate families.
///
///   Bebas Neue     → display headings only
///   Reddit Sans    → all UI, body, labels, the input editor
///   JetBrains Mono → the enhanced-prompt OUTPUT region only
enum VZFont {
  enum Weight {
    case regular
    case medium
    case semibold

    var postScriptName: String {
      switch self {
      case .regular: "RedditSans-Regular"
      case .medium: "RedditSans-Medium"
      case .semibold: "RedditSans-SemiBold"
      }
    }
  }

  static let displayName = "BebasNeue-Regular"
  static let monoName = "JetBrainsMono-Regular"
}

extension Font {
  /// Display face — headings, the wordmark. Sized relative to the given text
  /// style so Dynamic Type still scales it.
  static func vzDisplay(_ size: CGFloat, relativeTo style: TextStyle = .title) -> Font {
    .custom(VZFont.displayName, size: size, relativeTo: style)
  }

  static func vzBody(_ size: CGFloat = 15, _ weight: VZFont.Weight = .regular, relativeTo style: TextStyle = .body) -> Font {
    .custom(weight.postScriptName, size: size, relativeTo: style)
  }

  static func vzMono(_ size: CGFloat = 14, relativeTo style: TextStyle = .body) -> Font {
    .custom(VZFont.monoName, size: size, relativeTo: style)
  }
}

extension View {
  /// Rail captions: tracked micro-caps in Silver.
  func vzCaps() -> some View {
    font(.vzBody(11, .medium, relativeTo: .caption))
      .textCase(.uppercase)
      .tracking(1.2)
      .foregroundStyle(VZ.muted)
  }
}
