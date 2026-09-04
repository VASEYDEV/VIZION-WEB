@testable import VizionCore
import XCTest

final class SVGPathTests: XCTestCase {
  static let glyph =
    "M 589.98,130.37 L 589.15,215.36 L 619.68,229.39 Z M 434.02,130.37 L 425.77,130.37 L 413.40,133.67 Z"

  func testParsesTheBrandGlyphShape() throws {
    let commands = try SVGPathParser.parse(Self.glyph)
    XCTAssertEqual(commands.count, 8)
    XCTAssertEqual(commands[0], .move(x: 589.98, y: 130.37))
    XCTAssertEqual(commands[3], .close)
    XCTAssertEqual(commands[4], .move(x: 434.02, y: 130.37))
  }

  func testRelativeAndShorthandCommands() throws {
    let commands = try SVGPathParser.parse("M10 10h5v5H0V0z")
    XCTAssertEqual(commands, [
      .move(x: 10, y: 10), .line(x: 15, y: 10), .line(x: 15, y: 15), .line(x: 0, y: 15),
      .line(x: 0, y: 0), .close,
    ])
    let implicit = try SVGPathParser.parse("m1 1 2 2 3 3")
    XCTAssertEqual(implicit, [.move(x: 1, y: 1), .line(x: 3, y: 3), .line(x: 6, y: 6)])
  }

  func testCompactNumbersAndArcFlags() throws {
    // Simple Icons style: no separators between a negative number, a
    // leading-dot decimal, or packed arc flags.
    let commands = try SVGPathParser.parse("M0 0a.5.5 0 01.5.5l-1-1")
    XCTAssertEqual(commands.first, .move(x: 0, y: 0))
    let cubics = commands.compactMap { cmd -> SVGPathCommand? in
      if case .cubic = cmd {
        return cmd
      }
      return nil
    }
    XCTAssertGreaterThanOrEqual(cubics.count, 1)
    // The arc ends at (0.5, 0.5); the relative line then lands at (-0.5, -0.5).
    if case let .cubic(_, _, _, _, x, y) = try XCTUnwrap(cubics.last) {
      XCTAssertEqual(x, 0.5, accuracy: 1e-9)
      XCTAssertEqual(y, 0.5, accuracy: 1e-9)
    }
    XCTAssertEqual(commands.last, .line(x: -0.5, y: -0.5))
    // An implicit arc repeat needs all seven parameters.
    let repeated = try SVGPathParser.parse("M0 0a1 1 0 0 1 1 1 1 1 0 0 1 1 1")
    XCTAssertEqual(try XCTUnwrap(SVGPathParser.bounds(repeated)?.maxX), 2, accuracy: 1e-6)
    XCTAssertThrowsError(try SVGPathParser.parse("M0 0a.5.5 0 01.5.5-1-1"))
  }

  func testArcConversionIsAccurate() throws {
    // A half circle of radius 10 from (0,0) to (20,0): the midpoint of the
    // curve must sit on the circle at (10, ±10).
    let commands = try SVGPathParser.parse("M0 0A10 10 0 0 1 20 0")
    XCTAssertEqual(commands.count, 3, "two ≤90° cubics")
    guard case let .cubic(_, _, _, _, x, y) = commands[1] else { return XCTFail("cubic expected") }
    XCTAssertEqual(x, 10, accuracy: 1e-6)
    XCTAssertEqual(abs(y), 10, accuracy: 1e-6)
    let bounds = try XCTUnwrap(SVGPathParser.bounds(commands))
    XCTAssertEqual(bounds.minX, 0, accuracy: 1e-6)
    XCTAssertEqual(bounds.maxX, 20, accuracy: 1e-6)
  }

  func testEveryDeveloperMarkParses() throws {
    for (developer, mark) in DeveloperMark.paths {
      let commands = try SVGPathParser.parse(mark.d)
      XCTAssertFalse(commands.isEmpty, "\(developer) produced no geometry")
      let bounds = try XCTUnwrap(SVGPathParser.bounds(commands))
      XCTAssertLessThanOrEqual(
        bounds.maxX,
        mark.viewBoxWidth * 1.05,
        "\(developer) overflows its viewBox"
      )
      XCTAssertLessThanOrEqual(
        bounds.maxY,
        mark.viewBoxHeight * 1.05,
        "\(developer) overflows its viewBox"
      )
    }
    XCTAssertEqual(DeveloperMark.paths.count, Developer.allCases.count)
  }

  func testBrandGlyphMatchesTheSourceArtwork() throws {
    let commands = try SVGPathParser.parse(BrandGlyph.pathData)
    let bounds = try XCTUnwrap(SVGPathParser.bounds(commands))
    XCTAssertEqual(bounds.minX, 19.8, accuracy: 0.01)
    XCTAssertEqual(bounds.maxY, 873.0, accuracy: 0.01)
    XCTAssertEqual(
      commands.filter { $0 == .close }.count,
      4,
      "chevron, bar, and the two ring halves"
    )
  }

  func testErrors() {
    XCTAssertThrowsError(try SVGPathParser.parse("M 1"))
    XCTAssertThrowsError(try SVGPathParser.parse("X 1 2"))
  }
}
