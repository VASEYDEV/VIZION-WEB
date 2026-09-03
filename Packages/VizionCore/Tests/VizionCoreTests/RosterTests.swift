import XCTest
@testable import VizionCore

final class RosterTests: XCTestCase {
  func testSixteenTargetsGroupedContiguouslyInDeveloperOrder() {
    XCTAssertEqual(TargetModel.allCases.count, 16)
    XCTAssertEqual(Developer.allCases.count, 12)
    // Roster order is grouped by developer in Developer.allCases order.
    var lastIndex = -1
    for target in TargetModel.allCases {
      let index = Developer.allCases.firstIndex(of: target.developer)!
      XCTAssertGreaterThanOrEqual(index, lastIndex, "\(target) breaks developer grouping")
      lastIndex = index
    }
    XCTAssertEqual(TargetModel.grouped.map(\.developer), Developer.allCases)
    XCTAssertEqual(TargetModel.grouped.flatMap(\.models), TargetModel.allCases)
  }

  func testAnthropicAndOpenAILeadTheRoster() {
    XCTAssertEqual(TargetModel.allCases.prefix(3).map(\.developer), [.anthropic, .anthropic, .anthropic])
    XCTAssertEqual(TargetModel.allCases[3...5].map(\.developer), [.openai, .openai, .openai])
    XCTAssertEqual(TargetModel.allCases[3...5].map(\.label), ["GPT-5.6 Sol", "GPT-5.6 Terra", "GPT-5.6 Luna"])
  }

  func testWireIdsMatchTheDatabaseEnum() {
    let expected: Set<String> = [
      "opus_5", "sonnet_5", "gpt_5_6_sol", "fable_5", "deepseek_v4", "gemini_3_6_flash",
      "muse_spark_1_1", "minimax_m3", "mistral_large_3", "kimi_k3", "sonar_pro", "qwen3_8_max",
      "grok_4_5", "glm_5_2", "gpt_5_6_luna", "gpt_5_6_terra",
    ]
    XCTAssertEqual(Set(TargetModel.allCases.map(\.rawValue)), expected)
  }

  func testLegacyIdsResolveToLiveTargetsOnly() {
    for (legacy, current) in TargetModel.legacyIDs {
      XCTAssertNil(TargetModel(rawValue: legacy), "\(legacy) is still a live id")
      XCTAssertEqual(TargetModel.resolve(legacy), current)
    }
    XCTAssertEqual(TargetModel.resolve("gemini_pro_3_1"), .gemini36Flash)
    XCTAssertNil(TargetModel.resolve("not_a_model"))
    XCTAssertEqual(TargetModel.label(forRaw: "not_a_model"), "not_a_model")
  }

  func testThinkingLaddersMatchProviders() {
    XCTAssertEqual(TargetModel.fable5.thinkingLadder, [.low, .medium, .high, .xhigh, .max])
    XCTAssertEqual(TargetModel.grok45.thinkingLadder, [.low, .medium, .high])
    XCTAssertEqual(TargetModel.gemini36Flash.thinkingLadder, [.minimal, .low, .medium, .high])
    XCTAssertEqual(TargetModel.qwen38Max.thinkingLadder.count, 5)
    XCTAssertFalse(TargetModel.deepseekV4.hasThinkingDial)
    XCTAssertFalse(TargetModel.sonarPro.hasThinkingDial)
    let dial = ThinkingDial.detents(for: TargetModel.grok45.thinkingLadder)
    XCTAssertEqual(dial.map(\.id), ["auto", "low", "medium", "high"])
    XCTAssertEqual(dial.first?.tone, .faint)
    XCTAssertEqual(ThinkingLevel.high.tone, .steel)
    XCTAssertEqual(ThinkingLevel.max.tone, .ultra)
  }

  func testModesDisplayOrderAndLabels() {
    XCTAssertEqual(EnhanceMode.allCases.map(\.label), ["Clarify", "Polish", "Expand", "Condense", "Reformat", "Adapt"])
    XCTAssertEqual(EnhanceMode.target.rawValue, "target")
    XCTAssertTrue(EnhanceMode.polish.isShapePreserving)
    XCTAssertFalse(EnhanceMode.expand.isShapePreserving)
    XCTAssertEqual(EnhanceMode.label(forRaw: "target"), "Adapt")
    XCTAssertEqual(EnhanceMode.label(forRaw: "legacy_mode"), "legacy_mode")
  }

  func testLengthLabelsArePerMode() {
    XCTAssertEqual(EnhanceMode.condense.lengthOptions?.map(\.label), ["Tight", "Balanced", "Essential"])
    XCTAssertEqual(EnhanceMode.expand.lengthOptions?.map(\.label), ["Focused", "Thorough", "Comprehensive"])
    XCTAssertNil(EnhanceMode.polish.lengthOptions)
  }

  func testBudgetDetentsAreCheapestFirst() {
    XCTAssertEqual(AutoPreference.detents.map(\.id), ["budget", "balanced", "quality"])
    XCTAssertEqual(AutoPreference.allCases.map(\.rawValue), ["quality", "balanced", "budget"])
  }

  func testDeveloperAccentsAreHex() {
    for developer in Developer.allCases {
      XCTAssertEqual(developer.accentHex.count, 7)
      XCTAssertTrue(developer.accentHex.hasPrefix("#"))
    }
  }
}
