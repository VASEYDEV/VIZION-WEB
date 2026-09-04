import Foundation

/// A minimal SVG path-data parser: every brand and developer mark VIZION draws
/// is a single monochrome path (web: BrandMark, DeveloperIcon, ModeRig icons),
/// so the app renders them from the same `d` strings the web ships. Arcs are
/// converted to cubic Béziers; the output is plain geometry the SwiftUI layer
/// turns into a `Path`. Pure, so it tests on Linux.
public enum SVGPathCommand: Sendable, Hashable {
  case move(x: Double, y: Double)
  case line(x: Double, y: Double)
  case cubic(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
  case quad(x1: Double, y1: Double, x: Double, y: Double)
  case close
}

public struct SVGPathParseError: Error, Sendable, Hashable {
  public let message: String
  public let offset: Int
}

public enum SVGPathParser {
  // The command switch IS the grammar; splitting it per letter would scatter
  // the shared cursor/control-point state across a dozen functions.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  public static func parse(_ d: String) throws -> [SVGPathCommand] {
    var scanner = Scanner(Array(d.utf8))
    var commands: [SVGPathCommand] = []
    var current = (x: 0.0, y: 0.0)
    var subpathStart = (x: 0.0, y: 0.0)
    var lastControl: (x: Double, y: Double)?
    var lastCommand: UInt8 = 0

    while let cmd = scanner.nextCommand() {
      let isRelative = cmd >= 97 // lowercase
      let upper = isRelative ? cmd - 32 : cmd
      switch upper {
      case 77: // M
        var first = true
        repeat {
          let x = try scanner.number()
          let y = try scanner.number()
          let px = isRelative ? current.x + x : x
          let py = isRelative ? current.y + y : y
          commands.append(first ? .move(x: px, y: py) : .line(x: px, y: py))
          if first {
            subpathStart = (px, py)
          }
          current = (px, py)
          first = false
        } while scanner.hasNumber()
        lastControl = nil
      case 76: // L
        repeat {
          let x = try scanner.number()
          let y = try scanner.number()
          current = (isRelative ? current.x + x : x, isRelative ? current.y + y : y)
          commands.append(.line(x: current.x, y: current.y))
        } while scanner.hasNumber()
        lastControl = nil
      case 72: // H
        repeat {
          let x = try scanner.number()
          current.x = isRelative ? current.x + x : x
          commands.append(.line(x: current.x, y: current.y))
        } while scanner.hasNumber()
        lastControl = nil
      case 86: // V
        repeat {
          let y = try scanner.number()
          current.y = isRelative ? current.y + y : y
          commands.append(.line(x: current.x, y: current.y))
        } while scanner.hasNumber()
        lastControl = nil
      case 67: // C
        repeat {
          var p = [Double]()
          for _ in 0 ..< 6 {
            try p.append(scanner.number())
          }
          let base: (x: Double, y: Double) = isRelative ? current : (x: 0, y: 0)
          let c1 = (base.x + p[0], base.y + p[1])
          let c2 = (base.x + p[2], base.y + p[3])
          let end = (base.x + p[4], base.y + p[5])
          commands.append(.cubic(x1: c1.0, y1: c1.1, x2: c2.0, y2: c2.1, x: end.0, y: end.1))
          lastControl = c2
          current = end
        } while scanner.hasNumber()
      case 83: // S
        repeat {
          var p = [Double]()
          for _ in 0 ..< 4 {
            try p.append(scanner.number())
          }
          let base: (x: Double, y: Double) = isRelative ? current : (x: 0, y: 0)
          let c1: (Double, Double) = if lastCommand == 67 || lastCommand == 99 || lastCommand ==
            83 ||
            lastCommand == 115,
            let lc = lastControl {
            (2 * current.x - lc.x, 2 * current.y - lc.y)
          } else {
            (current.x, current.y)
          }
          let c2 = (base.x + p[0], base.y + p[1])
          let end = (base.x + p[2], base.y + p[3])
          commands.append(.cubic(x1: c1.0, y1: c1.1, x2: c2.0, y2: c2.1, x: end.0, y: end.1))
          lastControl = c2
          current = end
        } while scanner.hasNumber()
      case 81: // Q
        repeat {
          var p = [Double]()
          for _ in 0 ..< 4 {
            try p.append(scanner.number())
          }
          let base: (x: Double, y: Double) = isRelative ? current : (x: 0, y: 0)
          let c = (base.x + p[0], base.y + p[1])
          let end = (base.x + p[2], base.y + p[3])
          commands.append(.quad(x1: c.0, y1: c.1, x: end.0, y: end.1))
          lastControl = c
          current = end
        } while scanner.hasNumber()
      case 84: // T
        repeat {
          let x = try scanner.number()
          let y = try scanner.number()
          let base: (x: Double, y: Double) = isRelative ? current : (x: 0, y: 0)
          let c: (Double, Double) = if lastCommand == 81 || lastCommand == 113 || lastCommand ==
            84 ||
            lastCommand == 116,
            let lc = lastControl {
            (2 * current.x - lc.x, 2 * current.y - lc.y)
          } else {
            (current.x, current.y)
          }
          let end = (base.x + x, base.y + y)
          commands.append(.quad(x1: c.0, y1: c.1, x: end.0, y: end.1))
          lastControl = c
          current = end
        } while scanner.hasNumber()
      case 65: // A
        repeat {
          let rx = try scanner.number()
          let ry = try scanner.number()
          let rotation = try scanner.number()
          let largeArc = try scanner.flag()
          let sweep = try scanner.flag()
          let x = try scanner.number()
          let y = try scanner.number()
          let end = (isRelative ? current.x + x : x, isRelative ? current.y + y : y)
          commands.append(
            contentsOf: Self.arcToCubics(
              from: current, rx: rx, ry: ry, rotationDegrees: rotation, largeArc: largeArc,
              sweep: sweep, to: end
            )
          )
          current = end
        } while scanner.hasNumber()
        lastControl = nil
      case 90: // Z
        commands.append(.close)
        current = subpathStart
        lastControl = nil
      default:
        throw SVGPathParseError(
          message: "Unknown command \(Character(UnicodeScalar(cmd)))",
          offset: scanner.index
        )
      }
      lastCommand = cmd
    }
    return commands
  }

  /// SVG 1.1 F.6.5 endpoint → center parameterization, then one cubic per
  /// ≤90° slice. Seven parameters because that is the arc command's arity.
  static func arcToCubics( // swiftlint:disable:this function_parameter_count
    from p1: (x: Double, y: Double), rx rxIn: Double, ry ryIn: Double, rotationDegrees: Double,
    largeArc: Bool, sweep: Bool, to p2: (x: Double, y: Double)
  ) -> [SVGPathCommand] {
    if p1.x == p2.x, p1.y == p2.y {
      return []
    }
    var rx = abs(rxIn)
    var ry = abs(ryIn)
    if rx == 0 || ry == 0 {
      return [.line(x: p2.x, y: p2.y)]
    }
    let phi = rotationDegrees * .pi / 180
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let dx2 = (p1.x - p2.x) / 2
    let dy2 = (p1.y - p2.y) / 2
    let x1p = cosPhi * dx2 + sinPhi * dy2
    let y1p = -sinPhi * dx2 + cosPhi * dy2
    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 {
      rx *= lambda.squareRoot()
      ry *= lambda.squareRoot()
    }
    let rx2 = rx * rx
    let ry2 = ry * ry
    let num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
    let den = rx2 * y1p * y1p + ry2 * x1p * x1p
    let coef = (largeArc != sweep ? 1.0 : -1.0) *
      (den == 0 ? 0 : Swift.max(0, num / den).squareRoot())
    let cxp = coef * (rx * y1p / ry)
    let cyp = coef * -(ry * x1p / rx)
    let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

    func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
      let dot = ux * vx + uy * vy
      let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
      guard len > 0 else { return 0 }
      var a = acos(Swift.max(-1, Swift.min(1, dot / len)))
      if ux * vy - uy * vx < 0 {
        a = -a
      }
      return a
    }
    let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if !sweep, delta > 0 {
      delta -= 2 * .pi
    }
    if sweep, delta < 0 {
      delta += 2 * .pi
    }

    let segments = Swift.max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / Double(segments)
    let t = 4.0 / 3.0 * tan(step / 4)
    var out: [SVGPathCommand] = []
    func map(_ ux: Double, _ uy: Double) -> (Double, Double) {
      (cx + rx * ux * cosPhi - ry * uy * sinPhi, cy + rx * ux * sinPhi + ry * uy * cosPhi)
    }
    for i in 0 ..< segments {
      let a1 = theta1 + Double(i) * step
      let a2 = a1 + step
      let c1u = (cos(a1) - t * sin(a1), sin(a1) + t * cos(a1))
      let c2u = (cos(a2) + t * sin(a2), sin(a2) - t * cos(a2))
      let endU = (cos(a2), sin(a2))
      let c1 = map(c1u.0, c1u.1)
      let c2 = map(c2u.0, c2u.1)
      let end = i == segments - 1 ? (p2.x, p2.y) : map(endU.0, endU.1)
      out.append(.cubic(x1: c1.0, y1: c1.1, x2: c2.0, y2: c2.1, x: end.0, y: end.1))
    }
    return out
  }

  /// Axis-aligned bounds of the parsed geometry (control points included).
  public static func bounds(_ commands: [SVGPathCommand])
    -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
    var minX = Double.infinity, minY = Double.infinity
    var maxX = -Double.infinity, maxY = -Double.infinity
    func include(_ x: Double, _ y: Double) {
      minX = Swift.min(minX, x)
      minY = Swift.min(minY, y)
      maxX = Swift.max(maxX, x)
      maxY = Swift.max(maxY, y)
    }
    for c in commands {
      switch c {
      case let .move(x, y), let .line(x, y): include(x, y)
      case let .cubic(x1, y1, x2, y2, x, y):
        include(x1, y1)
        include(x2, y2)
        include(x, y)
      case let .quad(x1, y1, x, y):
        include(x1, y1)
        include(x, y)
      case .close: break
      }
    }
    return minX.isFinite ? (minX, minY, maxX, maxY) : nil
  }

  struct Scanner {
    let bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func skipSeparators() {
      while index < bytes.count, bytes[index] == 32 || bytes[index] == 44 || bytes[index] == 9
        || bytes[index] == 10 || bytes[index] == 13 {
        index += 1
      }
    }

    mutating func nextCommand() -> UInt8? {
      skipSeparators()
      guard index < bytes.count else { return nil }
      let c = bytes[index]
      let isLetter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
      guard isLetter else { return nil }
      index += 1
      return c
    }

    func hasNumber() -> Bool {
      var i = index
      while i < bytes.count, bytes[i] == 32 || bytes[i] == 44 || bytes[i] == 9 || bytes[i] == 10
        || bytes[i] == 13 {
        i += 1
      }
      guard i < bytes.count else { return false }
      let c = bytes[i]
      return (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46
    }

    mutating func number() throws -> Double {
      skipSeparators()
      let start = index
      if index < bytes.count, bytes[index] == 45 || bytes[index] == 43 {
        index += 1
      }
      var sawDigit = false
      while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
        index += 1
        sawDigit = true
      }
      if index < bytes.count, bytes[index] == 46 {
        index += 1
        while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
          index += 1
          sawDigit = true
        }
      }
      if sawDigit, index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
        var j = index + 1
        if j < bytes.count, bytes[j] == 45 || bytes[j] == 43 {
          j += 1
        }
        if j < bytes.count, bytes[j] >= 48, bytes[j] <= 57 {
          index = j
          while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
            index += 1
          }
        }
      }
      guard sawDigit, let text = String(bytes: bytes[start ..< index], encoding: .utf8),
            let value = Double(text)
      else {
        throw SVGPathParseError(message: "Expected a number", offset: start)
      }
      return value
    }

    /// Arc flags are single characters and may be packed (`0 01.5`).
    mutating func flag() throws -> Bool {
      skipSeparators()
      guard index < bytes.count, bytes[index] == 48 || bytes[index] == 49 else {
        throw SVGPathParseError(message: "Expected an arc flag", offset: index)
      }
      let value = bytes[index] == 49
      index += 1
      return value
    }
  }
}
