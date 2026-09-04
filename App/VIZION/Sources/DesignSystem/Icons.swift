import SwiftUI
import VizionCore

/// 1.5px-stroke, rounded-join icons on a 24px grid (style-guide §1.4). The
/// six mode icons and the three tab icons are the web's own paths verbatim.
enum VZIcon: String, CaseIterable, Sendable {
  case enhance
  case library
  case settings
  case clarify
  case polish
  case expand
  case condense
  case reformat
  case adapt
  case chevronLeft
  case chevronRight
  case chevronDown
  case plus
  case star
  case archive
  case folder
  case close
  case undo
  case check
  case history
  case copy
  case share
  case trash
  case search
  case filter
  case paperclip
  case sparkle
  case refresh
  case paste
  case eye
  case send

  // swiftlint:disable line_length
  var d: String {
    switch self {
    case .enhance:
      "M12 3v4M12 17v4M3 12h4M17 12h4M6.3 6.3l2.8 2.8M14.9 14.9l2.8 2.8M17.7 6.3l-2.8 2.8M9.1 14.9l-2.8 2.8M14.4 12a2.4 2.4 0 1 1-4.8 0 2.4 2.4 0 0 1 4.8 0"
    case .library:
      "M5 4h11a2 2 0 0 1 2 2v14M7 4v16M5 20h13M10 8h4"
    case .settings:
      "M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0M12 3.5v2.2m0 12.6v2.2m8.5-8.5h-2.2M5.7 12H3.5m14.5-6-1.6 1.6M7.6 16.4 6 18m12 0-1.6-1.6M7.6 7.6 6 6"
    case .clarify:
      "M17 11a6 6 0 1 1-12 0 6 6 0 0 1 12 0m3 9-3.5-3.5"
    case .polish:
      "M4 20h4L18 10l-4-4L4 16v4zm9-13 4 4"
    case .expand:
      "M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5"
    case .condense:
      "M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5"
    case .reformat:
      "M4 6h16M4 12h10M4 18h13"
    case .adapt:
      "M19 12a7 7 0 1 1-14 0 7 7 0 0 1 14 0m-4.5 0a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0"
    case .chevronLeft: "M14.5 6L9 12l5.5 6"
    case .chevronRight: "M9.5 6 15 12l-5.5 6"
    case .chevronDown: "M6 9.5 12 15l6-5.5"
    case .plus: "M12 5v14M5 12h14"
    case .star: "m12 3.5 2.6 5.4 5.9.8-4.3 4.1 1.1 5.9L12 16.9l-5.3 2.8 1.1-5.9-4.3-4.1 5.9-.8z"
    case .archive: "M4 7h16v3H4zM5 10v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9M10 14h4"
    case .folder: "M3 7a1 1 0 0 1 1-1h5l2 2h9a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"
    case .close: "M6 6l12 12M18 6 6 18"
    case .undo: "M9 14 4 9l5-5M4 9h9a6 6 0 0 1 0 12h-2"
    case .check: "m5 12.5 4.5 4.5L19 7.5"
    case .history: "M4 4v5h5M4.5 9a8 8 0 1 1-.4 5M12 8v4l3 2"
    case .copy: "M9 9h10v11H9zM5 15V4h11"
    case .share: "M12 3v12M8 7l4-4 4 4M5 13v6a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-6"
    case .trash: "M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"
    case .search: "M16 10.5a5.5 5.5 0 1 1-11 0 5.5 5.5 0 0 1 11 0m4 9.5-5-5"
    case .filter: "M4 6h16M7 12h10M10 18h4"
    case .paperclip: "m8.5 12.5 6.4-6.4a2.5 2.5 0 0 1 3.5 3.5l-8 8a4.5 4.5 0 0 1-6.4-6.4l7.6-7.6"
    case .sparkle: "M12 4v4M12 16v4M4 12h4M16 12h4M7 7l1.5 1.5M15.5 15.5 17 17M17 7l-1.5 1.5M8.5 15.5 7 17"
    case .refresh: "M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5"
    case .paste: "M9 4h6v3H9zM7 6H6a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-1"
    case .eye: "M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6zm12 0a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0"
    case .send: "M4 12 20 5l-5 15-3-6z"
    }
  }

  // swiftlint:enable line_length

  var commands: [SVGPathCommand] {
    Self.cache[self] ?? []
  }

  private static let cache: [VZIcon: [SVGPathCommand]] = Dictionary(
    uniqueKeysWithValues: allCases.map { ($0, (try? SVGPathParser.parse($0.d)) ?? []) }
  )

  static func mode(_ mode: EnhanceMode) -> VZIcon {
    switch mode {
    case .clarify: .clarify
    case .polish: .polish
    case .expand: .expand
    case .condense: .condense
    case .reformat: .reformat
    case .target: .adapt
    }
  }
}

/// Stroked icon on the 24-grid. Stroke width scales with the frame so a 14pt
/// chip glyph keeps the same weight as a 24pt tab glyph.
struct IconView: View {
  var icon: VZIcon
  var size: CGFloat = 20
  var strokeWidth: CGFloat = 1.5
  var filled = false

  /// `nonisolated`: an explicit init on a View is main-actor isolated, and a
  /// PhotosPicker label closure is not — every stored value here is Sendable.
  nonisolated init(
    _ icon: VZIcon,
    size: CGFloat = 20,
    strokeWidth: CGFloat = 1.5,
    filled: Bool = false
  ) {
    self.icon = icon
    self.size = size
    self.strokeWidth = strokeWidth
    self.filled = filled
  }

  var body: some View {
    let shape = SVGShape(commands: icon.commands, viewBox: CGSize(width: 24, height: 24))
    ZStack {
      if filled {
        shape.fill(.primary)
      }
      shape.stroke(
        style: StrokeStyle(lineWidth: strokeWidth * (size / 24), lineCap: .round, lineJoin: .round)
      )
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
