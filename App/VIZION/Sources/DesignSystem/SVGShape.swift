import SwiftUI
import VizionCore

/// A SwiftUI `Shape` drawn from SVG path geometry, scaled to fit its frame
/// while preserving the viewBox aspect (like `<svg viewBox>` with the default
/// `xMidYMid meet`).
struct SVGShape: Shape {
  var commands: [SVGPathCommand]
  var viewBox: CGSize
  /// Applied in viewBox space before fitting (potrace exports are flipped).
  var transform: CGAffineTransform = .identity

  func path(in rect: CGRect) -> Path {
    guard viewBox.width > 0, viewBox.height > 0 else { return Path() }
    let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
    let offsetX = rect.minX + (rect.width - viewBox.width * scale) / 2
    let offsetY = rect.minY + (rect.height - viewBox.height * scale) / 2
    let fit = transform
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    return Path(svg: commands).applying(fit)
  }
}

extension Path {
  init(svg commands: [SVGPathCommand]) {
    self.init()
    for command in commands {
      switch command {
      case let .move(x, y):
        move(to: CGPoint(x: x, y: y))
      case let .line(x, y):
        addLine(to: CGPoint(x: x, y: y))
      case let .cubic(x1, y1, x2, y2, x, y):
        addCurve(
          to: CGPoint(x: x, y: y),
          control1: CGPoint(x: x1, y: y1),
          control2: CGPoint(x: x2, y: y2)
        )
      case let .quad(x1, y1, x, y):
        addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x1, y: y1))
      case .close:
        closeSubpath()
      }
    }
  }
}
