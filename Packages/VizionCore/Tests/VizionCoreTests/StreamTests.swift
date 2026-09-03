import XCTest
@testable import VizionCore

final class StreamTests: XCTestCase {
  func testParserHandlesSplitFramesAndMultipleFramesPerChunk() {
    var parser = SSEParser()
    let chunk1 = Array("data: {\"type\":\"status\",\"step\":\"queued\",\"label\":\"Queued\"}\n\ndata: {\"type\":\"del".utf8)
    let chunk2 = Array("ta\",\"text\":\"Hel\"}\n\ndata: {\"type\":\"delta\",\"text\":\"lo\"}\n\n".utf8)
    let first = parser.feed(chunk1)
    XCTAssertEqual(first, [.status(step: .queued, label: "Queued")])
    let second = parser.feed(chunk2)
    XCTAssertEqual(second, [.delta(text: "Hel"), .delta(text: "lo")])
    XCTAssertEqual(parser.finish(), [])
  }

  func testGarbledFramesAreSkippedAndCRLFAccepted() {
    let body = "data: not json\r\n\r\ndata: {\"type\":\"usage\",\"tokenIn\":10,\"tokenOut\":2,\"snapshot\":true}\r\n\r\n"
    let events = SSEParser.parse(Data(body.utf8))
    XCTAssertEqual(events, [.usage(tokenIn: 10, tokenOut: 2, costUsd: nil, snapshot: true)])
  }

  func testDoneAndErrorDecode() throws {
    // One JSON object per `data:` line — a raw newline inside the payload
    // would end the line, exactly as the web parser reads it.
    let done = "data: {\"type\":\"done\",\"result\":{\"output\":\"o\",\"rationale\":\"r\",\"diff\":null,\"tokenIn\":1,\"tokenOut\":2,\"modelUsed\":\"claude-opus-5\",\"costUsd\":0.01,\"usage\":{\"todayCost\":0.5,\"capUsd\":2},\"resolvedTarget\":\"sonnet_5\",\"resolvedReason\":\"light-task\",\"questions\":[\"Q?\"]}}\n\n"
      + "data: {\"type\":\"error\",\"status\":503,\"error\":\"nope\",\"notConfigured\":true}\n\n"
    let events = SSEParser.parse(Data(done.utf8))
    XCTAssertEqual(events.count, 2)
    guard case let .done(result) = events[0] else { return XCTFail("expected done") }
    XCTAssertNil(result.diff)
    XCTAssertEqual(result.resolvedTarget, .sonnet5)
    XCTAssertEqual(result.resolvedReasonLabel, "quick task")
    XCTAssertEqual(result.questions, ["Q?"])
    XCTAssertEqual(result.capFraction, 0.25, accuracy: 0.0001)
    XCTAssertEqual(events[1], .error(status: 503, message: "nope", notConfigured: true, capReached: false))
  }

  func testUnknownResolvedReasonRendersNothing() throws {
    let result = try JSONDecoder().decode(
      EnhanceResult.self,
      from: Data(
        """
        {"output":"o","rationale":"r","diff":[{"op":"equal","text":"o"}],"tokenIn":1,"tokenOut":1,
         "modelUsed":"m","costUsd":0,"usage":{"todayCost":0,"capUsd":2},"resolvedReason":"future-reason"}
        """.utf8))
    XCTAssertNil(result.resolvedReasonLabel)
    XCTAssertEqual(result.diff?.count, 1)
  }

  func testStreamStateMonotonicCounters() {
    var state = EnhanceStreamState.started()
    XCTAssertTrue(state.active)
    XCTAssertEqual(state.step, "Queued")
    // Anthropic-style snapshot: a placeholder must not pin the ticker.
    state.apply(.usage(tokenIn: 1213, tokenOut: 1, costUsd: nil, snapshot: true))
    XCTAssertFalse(state.usageMeasured)
    state.apply(.delta(text: String(repeating: "x", count: 400)))
    XCTAssertEqual(state.tokenOut, 100)
    XCTAssertEqual(state.costUsd, 0)
    // A real measurement REPLACES and stands the estimator down.
    state.apply(.usage(tokenIn: 1300, tokenOut: 90, costUsd: 0.02, snapshot: false))
    XCTAssertTrue(state.usageMeasured)
    XCTAssertEqual(state.tokenOut, 90)
    XCTAssertEqual(state.tokenIn, 1300)
    state.apply(.delta(text: String(repeating: "y", count: 4_000)))
    XCTAssertEqual(state.tokenOut, 90, "estimator stands down after a measurement")
    // A late snapshot may only raise.
    state.apply(.usage(tokenIn: 1000, tokenOut: 50, costUsd: 0.01, snapshot: true))
    XCTAssertEqual(state.tokenIn, 1300)
    XCTAssertEqual(state.tokenOut, 90)
    XCTAssertEqual(state.costUsd, 0.02)
    state.apply(.status(step: .diffing, label: "Building the diff…"))
    XCTAssertEqual(state.step, "Building the diff…")
  }

  func testRequestEncodingOmitsInertKnobs() throws {
    let req = EnhanceRequest(
      input: "hi", mode: .polish, target: .opus5, auto: false, autoPreference: .quality,
      format: .json, length: .long, thinkingLevel: .high, mediaContext: []
    )
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as! [String: Any]
    XCTAssertEqual(json["input"] as? String, "hi")
    XCTAssertEqual(json["mode"] as? String, "polish")
    XCTAssertEqual(json["target"] as? String, "opus_5")
    XCTAssertEqual(json["thinkingLevel"] as? String, "high")
    XCTAssertNil(json["auto"])
    XCTAssertNil(json["autoPreference"])
    XCTAssertNil(json["format"], "format is inert outside Reformat")
    XCTAssertNil(json["length"], "length is inert outside Condense/Expand")
    XCTAssertNil(json["mediaContext"])
    XCTAssertNil(json["refine"])

    let auto = EnhanceRequest(input: "hi", mode: .reformat, target: .opus5, auto: true, autoPreference: .budget, format: .xml)
    let autoJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(auto)) as! [String: Any]
    XCTAssertEqual(autoJSON["auto"] as? Bool, true)
    XCTAssertEqual(autoJSON["autoPreference"] as? String, "budget")
    XCTAssertEqual(autoJSON["format"] as? String, "xml")
  }

  func testRequestValidation() {
    XCTAssertEqual(EnhanceRequest(input: "   ", mode: .clarify, target: .opus5).validate(), "Provide a prompt to enhance.")
    XCTAssertNotNil(EnhanceRequest(input: String(repeating: "a", count: 20_001), mode: .clarify, target: .opus5).validate())
    XCTAssertNotNil(EnhanceRequest(input: "x", mode: .clarify, target: .deepseekV4, thinkingLevel: .high).validate())
    XCTAssertNil(EnhanceRequest(input: "x", mode: .clarify, target: .deepseekV4, auto: true, thinkingLevel: .high).validate(), "under Auto an out-of-ladder level is advisory")
  }

  func testAnswersBlock() {
    let block = EnhanceRefine.answersBlock(questions: ["Who?", "Why?"], answers: ["Me ", "Because"])
    XCTAssertEqual(block, "Q: Who?\nA: Me\n\nQ: Why?\nA: Because")
  }

  func testExports() {
    let d = ExportData(input: "in", output: "out \"q\"", rationale: "why", mode: .target, target: .kimiK3, modelUsed: "kimi-k3")
    XCTAssertTrue(ExportFormat.markdown.render(d).hasPrefix("# VIZION — Adapt → Kimi K3\n"))
    XCTAssertEqual(ExportFormat.text.render(d), "out \"q\"\n")
    let json = ExportFormat.json.render(d)
    let parsed = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: String]
    XCTAssertEqual(parsed["mode"], "target")
    XCTAssertEqual(parsed["output"], "out \"q\"")
    XCTAssertTrue(json.hasPrefix("{\n  \"mode\": \"target\",\n  \"target\": \"kimi_k3\""))
  }
}
