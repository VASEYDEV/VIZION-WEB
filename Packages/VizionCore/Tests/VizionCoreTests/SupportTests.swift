@testable import VizionCore
import XCTest

final class SupportTests: XCTestCase {
  func testPostgresDateParsesMicrosecondsAndOffsets() throws {
    let a = try XCTUnwrap(PostgresDate.parse("2026-08-15T11:30:00.123456+00:00"))
    XCTAssertEqual(a.timeIntervalSince1970, 1_786_793_400.123456, accuracy: 0.001)
    let b = try XCTUnwrap(PostgresDate.parse("2026-08-15T11:30:00Z"))
    XCTAssertEqual(b.timeIntervalSince1970, 1_786_793_400, accuracy: 0.001)
    let c = try XCTUnwrap(PostgresDate.parse("2026-08-15 13:30:00+02"))
    XCTAssertEqual(c.timeIntervalSince1970, 1_786_793_400, accuracy: 0.001)
    let d = try XCTUnwrap(PostgresDate.parse("2026-08-15T06:30:00.5-05:00"))
    XCTAssertEqual(d.timeIntervalSince1970, 1_786_793_400.5, accuracy: 0.001)
    XCTAssertNil(PostgresDate.parse("yesterday"))
    XCTAssertNil(PostgresDate.parse("2026-13-40T00:00:00Z"))
    XCTAssertNil(PostgresDate.parse("2026-02-30T00:00:00Z"))
    XCTAssertNotNil(PostgresDate.parse("2028-02-29T00:00:00Z"))
    let formatted = PostgresDate.format(Date(timeIntervalSince1970: 1_786_793_400.5))
    XCTAssertEqual(formatted, "2026-08-15T11:30:00.500Z")
  }

  func testPasswordRule() {
    XCTAssertEqual(PasswordRule.validate("short"), "Use at least 12 characters.")
    XCTAssertEqual(PasswordRule.validate("alllowercase12"), "Add an uppercase letter.")
    XCTAssertEqual(PasswordRule.validate("nodigitsHERExx"), "Add a number.")
    XCTAssertEqual(
      PasswordRule.validate("123456789012"),
      "Add a lowercase letter and an uppercase letter."
    )
    XCTAssertNil(PasswordRule.validate("Correct Horse 9"))
    XCTAssertTrue(Onboarding.needsPassword(authMethod: .magicLink, passwordSet: false))
    XCTAssertFalse(Onboarding.needsPassword(authMethod: .github, passwordSet: false))
  }

  func testDeepLinks() throws {
    XCTAssertEqual(
      try DeepLink.parse(XCTUnwrap(URL(string: "vizion://enhance?draft=hello%20world"))),
      .enhance(draft: "hello world")
    )
    XCTAssertEqual(
      try DeepLink.parse(XCTUnwrap(URL(string: "https://vizion-io.vercel.app/enhance?draft=x"))),
      .enhance(draft: "x")
    )
    XCTAssertEqual(try DeepLink.parse(XCTUnwrap(URL(string: "vizion://library"))), .library)
    XCTAssertEqual(
      try DeepLink
        .parse(XCTUnwrap(URL(string: "vizion://library/123e4567-e89b-12d3-a456-426614174000"))),
      .prompt(id: "123e4567-e89b-12d3-a456-426614174000")
    )
    XCTAssertEqual(
      try DeepLink.parse(XCTUnwrap(URL(string: "vizion://library/not-a-uuid"))),
      .library
    )
    XCTAssertEqual(try DeepLink.parse(XCTUnwrap(URL(string: "vizion://profile"))), .settings)
    let cb = try XCTUnwrap(URL(string: "vizion://auth/callback?code=abc"))
    XCTAssertEqual(DeepLink.parse(cb), .authCallback(cb))
    XCTAssertEqual(
      try DeepLink.parse(XCTUnwrap(URL(string: "vizion://auth/callback?error=access_denied"))),
      .authError("access_denied")
    )
    XCTAssertNil(try DeepLink.parse(XCTUnwrap(URL(string: "mailto:x@y.z"))))
    XCTAssertNil(try DeepLink.parse(XCTUnwrap(URL(string: "vizion://nope"))))
  }

  func testDraftParam() {
    XCTAssertEqual(DraftParam.resolve(nil, currentDraft: ""), .none)
    XCTAssertEqual(DraftParam.resolve("  ", currentDraft: ""), .none)
    XCTAssertEqual(DraftParam.resolve(" hi ", currentDraft: ""), .apply("hi"))
    XCTAssertEqual(DraftParam.resolve("hi", currentDraft: "work"), .conflict("hi"))
    XCTAssertEqual(DraftParam.resolve(String(repeating: "a", count: 8001), currentDraft: ""), .none)
  }

  func testMediaHelpers() {
    XCTAssertEqual(MediaKind.kind(forMIME: "image/jpeg"), .image)
    XCTAssertEqual(MediaKind.kind(forMIME: "video/quicktime"), .video)
    XCTAssertNil(MediaKind.kind(forMIME: "image/heic"))
    XCTAssertEqual(MediaKind.fileExtension(forMIME: "image/jpeg"), "jpg")
    XCTAssertEqual(AttachmentRole.roles(for: .audio), [.reference, .generate])
    XCTAssertEqual(AttachmentRole.extract.analysisIntent, .extractText)
    XCTAssertEqual(AttachmentRole.describe.requestIntent, .describe)
    XCTAssertEqual(AttachmentRole.describe.analysisIntent, .reference)
    XCTAssertEqual(AttachmentRole.generate.requestIntent, .reference)
    XCTAssertEqual(GenTarget.default(for: .video), .runway)
    XCTAssertEqual(
      MediaAnalysisRequest.dataURL(mime: "image/png", base64: "AAAA"),
      "data:image/png;base64,AAAA"
    )
    XCTAssertEqual(MediaBudget.formatBytes(500), "500 B")
    XCTAssertEqual(MediaBudget.formatBytes(2048), "2 KB")
    XCTAssertEqual(MediaBudget.formatBytes(3 * 1024 * 1024 + 1), "3.0 MB")
    XCTAssertTrue(MediaBudget.status(usedBytes: 41 * 1024 * 1024).warn)
    XCTAssertFalse(MediaBudget.status(usedBytes: 41 * 1024 * 1024).over)
  }

  func testMediaContextBuilder() {
    XCTAssertEqual(MediaContext.sanitizeName("a\u{01}b.png"), "ab.png")
    XCTAssertEqual(MediaContext.sanitizeName(""), "untitled")
    let long = String(repeating: "x", count: 50)
    XCTAssertEqual(MediaContext.sanitizeName(long, max: 11).count, 11)
    let items = [
      MediaContextItem(
        role: .reference,
        isReady: true,
        name: "ref.png",
        description: "A red door.",
        attrs: nil
      ),
      MediaContextItem(
        role: .reference,
        isReady: false,
        name: "pending.png",
        description: "x",
        attrs: nil
      ),
      MediaContextItem(
        role: .style,
        isReady: true,
        name: "style.png",
        description: "y",
        attrs: nil
      ),
      MediaContextItem(
        role: .reference, isReady: true, name: "attrs.png", description: nil,
        attrs: MediaAttributes(subject: "cat", style: "noir", width: 10, height: 20)
      ),
    ]
    let blocks = MediaContext.build(items)
    XCTAssertEqual(blocks, [
      "Visual reference (ref.png): A red door.",
      "Visual reference (attrs.png): cat, noir style, 10×20",
    ])
    XCTAssertEqual(
      MediaContext.styleSnippet(MediaAttributes(palette: ["#000"], lighting: "soft", style: "oil")),
      "Style reference: oil; soft lighting; palette #000"
    )
    XCTAssertEqual(MediaContext.styleSnippet(MediaAttributes()), "")
  }

  func testGenerationFormatters() {
    let attrs = MediaAttributes(
      subject: "lighthouse",
      palette: ["#0a1e28", "#3fd4e8"],
      mood: "moody",
      width: 1080,
      height: 1920
    )
    XCTAssertEqual(
      GenerationPrompt.build(base: "At dusk", attrs: attrs, target: .midjourney),
      "At dusk, lighthouse, moody mood, palette #0a1e28 #3fd4e8 --ar 9:16 --v 6"
    )
    XCTAssertEqual(
      GenerationPrompt.build(base: "At dusk", attrs: MediaAttributes(), target: .midjourney),
      "At dusk --ar 16:9 --v 6"
    )
    XCTAssertEqual(
      GenerationPrompt.build(base: "Slow pan", attrs: attrs, target: .runway),
      "[runway] Slow pan Subject: lighthouse. Mood: moody. Palette: #0a1e28, #3fd4e8."
    )
    XCTAssertEqual(
      GenerationPrompt.build(
        base: "Ambient",
        attrs: MediaAttributes(mood: "calm", durationSec: 29.6),
        target: .audio
      ),
      "Ambient Mood: calm. Duration: ~30s."
    )
    XCTAssertEqual(
      GenerationPrompt.nearestAspect(width: 2000, height: 1000),
      "16:9",
      "2.0 is nearer 16:9 (1.78) than 21:9 (2.33)"
    )
    XCTAssertEqual(GenerationPrompt.nearestAspect(width: 2100, height: 900), "21:9")
  }
}
