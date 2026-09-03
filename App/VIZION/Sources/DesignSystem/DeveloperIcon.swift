import SwiftUI
import VizionCore

/// A model-developer mark on `currentColor`. Pair with `VZ.accent` for AA in
/// both themes; on a Laser fill pass `VZ.onLaser`.
struct DeveloperIcon: View {
  var developer: Developer
  var size: CGFloat = 16

  private static let cache: [Developer: [SVGPathCommand]] = Dictionary(
    uniqueKeysWithValues: Developer.allCases.map { developer in
      (developer, (try? SVGPathParser.parse(DeveloperMark.mark(for: developer).d)) ?? [])
    })

  var body: some View {
    let mark = DeveloperMark.mark(for: developer)
    SVGShape(
      commands: Self.cache[developer] ?? [],
      viewBox: CGSize(width: mark.viewBoxWidth, height: mark.viewBoxHeight)
    )
    .fill(style: FillStyle(eoFill: mark.evenOdd))
    .frame(width: size, height: size)
    .accessibilityLabel(developer.label)
  }
}

/// A developer mark for a raw stored target id — nothing for an unknown id
/// (a card must never blank-screen the list over a retired model).
struct TargetMark: View {
  var targetID: String
  var size: CGFloat = 16

  var body: some View {
    if let developer = TargetModel.developer(forRaw: targetID) {
      DeveloperIcon(developer: developer, size: size)
    }
  }
}
