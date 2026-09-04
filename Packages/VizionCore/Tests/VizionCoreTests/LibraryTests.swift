@testable import VizionCore
import XCTest

final class LibraryTests: XCTestCase {
  func testContentHashMatchesSha256Vector() {
    // sha256("abc") — the FIPS vector — proves the digest; the hash then
    // joins the four fields with US (0x1f).
    XCTAssertEqual(
      SHA256.hex(Array("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
    XCTAssertEqual(
      SHA256.hex([]),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
    let h1 = LibraryUtil.contentHash(input: "in", output: "out", mode: "polish", target: "opus_5")
    let h2 = LibraryUtil.contentHash(input: "in", output: "out", mode: "polish", target: "kimi_k3")
    XCTAssertEqual(h1.count, 64)
    XCTAssertNotEqual(h1, h2, "the same content for a different target is a distinct prompt")
    XCTAssertEqual(
      h1, SHA256.hex(Array("in\u{1F}out\u{1F}polish\u{1F}opus_5".utf8))
    )
  }

  func testLongMessageHash() {
    let million = [UInt8](repeating: 0x61, count: 1_000_000)
    XCTAssertEqual(
      SHA256.hex(million),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
    )
  }

  func testDeriveTitle() {
    XCTAssertEqual(LibraryUtil.deriveTitle("  \n\n  "), "Untitled prompt")
    XCTAssertEqual(LibraryUtil.deriveTitle("First line\nSecond"), "First line")
    let long = String(repeating: "word ", count: 30)
    let title = LibraryUtil.deriveTitle(long)
    XCTAssertTrue(title.hasSuffix("…"))
    XCTAssertLessThanOrEqual(title.count, 60)
  }

  func testParseTags() {
    XCTAssertEqual(LibraryUtil.parseTags("#Foo, bar,\nfoo , BAR, ,baz"), ["foo", "bar", "baz"])
  }

  func testRelativeTime() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(LibraryUtil.relativeTime(now.addingTimeInterval(-10), now: now), "Now")
    XCTAssertEqual(LibraryUtil.relativeTime(now.addingTimeInterval(-50), now: now), "1 min ago")
    XCTAssertEqual(LibraryUtil.relativeTime(now.addingTimeInterval(-3000), now: now), "50 min ago")
    XCTAssertEqual(LibraryUtil.relativeTime(now.addingTimeInterval(-7200), now: now), "2 hr ago")
    XCTAssertEqual(
      LibraryUtil.relativeTime(now.addingTimeInterval(-3 * 86400), now: now),
      "3 days ago"
    )
  }

  func testCursorRoundTripAndTamperRejection() {
    let id = "123e4567-e89b-12d3-a456-426614174000"
    let cursor = LibraryPaging.encodeCursor(value: "2026-08-15T11:30:00.123456+00:00", id: id)
    let decoded = LibraryPaging.decodeCursor(cursor)
    XCTAssertEqual(decoded?.value, "2026-08-15T11:30:00.123456+00:00")
    XCTAssertEqual(decoded?.id, id)
    XCTAssertNil(LibraryPaging.decodeCursor("no-separator"))
    XCTAssertNil(LibraryPaging.decodeCursor("v\u{1F}x,id.not.is.null"))
    XCTAssertNil(LibraryPaging.decodeCursor("\u{1F}\(id)"))
  }

  func testCursorExpressionQuotesEveryValue() {
    let id = "123e4567-e89b-12d3-a456-426614174000"
    let expr = LibraryPaging.cursorExpression(
      sort: .updated,
      cursor: (value: "2026-08-15T11:30:00+00:00", id: id)
    )
    XCTAssertEqual(
      expr,
      // swiftlint:disable:next line_length
      "updated_at.lt.\"2026-08-15T11:30:00+00:00\",and(updated_at.eq.\"2026-08-15T11:30:00+00:00\",id.lt.\(id))"
    )
    let titleExpr = LibraryPaging.cursorExpression(sort: .title, cursor: (value: "a,b\"c", id: id))
    XCTAssertTrue(titleExpr.hasPrefix("title.gt.\"a,b\\\"c\""))
  }

  func testEscapeLikeAndQuote() {
    XCTAssertEqual(LibraryPaging.escapeLike("100%_a\\b"), "100\\%\\_a\\\\b")
    XCTAssertEqual(LibraryPaging.quoteOrValue("say \"hi\""), "\"say \\\"hi\\\"\"")
    XCTAssertEqual(
      LibraryPaging.draftsSearchExpression("x"),
      "title.ilike.\"%x%\",body.ilike.\"%x%\""
    )
  }

  func testFilterDefaultsAndBadge() {
    XCTAssertEqual(LibraryFilter.default.activeCount, 0)
    XCTAssertTrue(LibraryFilter.default.isDefault)
    let f = LibraryFilter(
      q: "  hi  ",
      model: .opus5,
      collection: "not-a-uuid",
      view: .favorites,
      sort: .title
    )
    XCTAssertEqual(f.q, "hi")
    XCTAssertNil(f.collection)
    XCTAssertEqual(f.activeCount, 3)
    XCTAssertEqual(f.webPath(), "/library?q=hi&model=opus_5&view=favorites&sort=title")
  }

  func testFacetGrouping() throws {
    let single = [ModelFacet(id: "opus_5", count: 2), ModelFacet(id: "sonnet_5", count: 1)]
    XCTAssertNil(LibraryFacets.groupModels(single))
    let mixed = [
      ModelFacet(id: "kimi_k3", count: 3),
      ModelFacet(id: "opus_5", count: 2),
      ModelFacet(id: "retired_x", count: 1),
    ]
    let groups = try XCTUnwrap(LibraryFacets.groupModels(mixed))
    XCTAssertEqual(groups.map(\.label), ["Anthropic", "Moonshot AI", "Other"])
  }

  func testFacetReduce() {
    let facets = LibraryFacets.reduce(
      rows: [("opus_5", ["a", "b"], "c1"), ("opus_5", ["b"], nil), ("kimi_k3", [], "c1")],
      collections: [("c1", "Work"), ("c2", "Empty")]
    )
    XCTAssertEqual(facets.models.map(\.id), ["opus_5", "kimi_k3"])
    XCTAssertEqual(facets.tags, ["a", "b"])
    XCTAssertEqual(facets.collections.map(\.count), [2, 0])
  }

  func testPageRowToCard() throws {
    let json = """
    {"id":"1","title":"T","target_model":"opus_5","tags":["x"],"created_at":"2026-01-01T00:00:00+00:00",
     "updated_at":"2026-01-02T00:00:00+00:00","favorite":true,"archived_at":null,"deleted_at":null,
     "preview":"p","current_mode":"target","collection_id":null,"prompt_versions":[{"count":3}]}
    """
    let row = try JSONDecoder().decode(PromptPageRow.self, from: Data(json.utf8))
    let card = row.card
    XCTAssertEqual(card.versions, 3)
    XCTAssertEqual(card.modeLabel, "Adapt")
    XCTAssertEqual(card.developer, .anthropic)
    XCTAssertFalse(card.archived)
  }

  func testDisplayNameRule() {
    XCTAssertTrue(LibraryUtil.isValidDisplayName("sean_v-1"))
    XCTAssertFalse(LibraryUtil.isValidDisplayName("Sean"))
    XCTAssertFalse(LibraryUtil.isValidDisplayName("ab"))
  }
}
