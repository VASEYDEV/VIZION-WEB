@testable import VizionCore
import XCTest

final class DiffTests: XCTestCase {
  func testTokenizeKeepsWhitespaceRuns() {
    XCTAssertEqual(WordDiff.tokenize("a  b\nc"), ["a", "  ", "b", "\n", "c"])
    XCTAssertEqual(WordDiff.tokenize(""), [])
  }

  func testIdenticalTextIsOneEqualSegment() {
    let d = WordDiff.diffWords("hello world", "hello world")
    XCTAssertEqual(d, [DiffSegment(op: .equal, text: "hello world")])
  }

  func testReplacementInterleavesRemovedThenAdded() {
    let d = WordDiff.diffWords("the quick fox", "the slow fox")
    XCTAssertEqual(d.map(\.op), [.equal, .removed, .added, .equal])
    XCTAssertEqual(d[1].text, "quick")
    XCTAssertEqual(d[2].text, "slow")
    // Lossless reconstruction on both sides.
    XCTAssertEqual(d.filter { $0.op != .added }.map(\.text).joined(), "the quick fox")
    XCTAssertEqual(d.filter { $0.op != .removed }.map(\.text).joined(), "the slow fox")
  }

  func testAdditionsAndDeletions() {
    XCTAssertEqual(WordDiff.diffWords("", "new text").map(\.op), [.added])
    XCTAssertEqual(WordDiff.diffWords("old text", "").map(\.op), [.removed])
  }

  func testBoundedDiffRefusesOversizedInput() {
    let big = Array(repeating: "w", count: 2001).joined(separator: " ")
    XCTAssertNil(WordDiff.boundedDiffWords(big, "x"))
    XCTAssertNotNil(WordDiff.boundedDiffWords("a b", "a c"))
  }

  func testHunksBridgeWhitespaceAndCountSections() {
    let d = WordDiff.diffWords("one two three four", "one 2 3 four")
    let hunks = WordDiff.hunks(d)
    XCTAssertEqual(hunks.count, 1)
    XCTAssertEqual(hunks[0].removed, "two three")
    XCTAssertEqual(hunks[0].added, "2 3")
    XCTAssertEqual(WordDiff.countChangedSections(d), 1)
  }

  func testApplyDecisionsInvariants() {
    let before = "Fix teh typo and remove this clause please."
    let after = "Fix the typo please."
    let d = WordDiff.diffWords(before, after)
    XCTAssertEqual(WordDiff.applyDecisions(d, rejected: []), after)
    let all = Set(WordDiff.hunks(d).map(\.index))
    XCTAssertEqual(WordDiff.applyDecisions(d, rejected: all), before)
    XCTAssertEqual(WordDiff.inputSide(d), before)
  }
}
