import XCTest
import VizionCore
@testable import VIZION

@MainActor
final class UIStoreTests: XCTestCase {
  private func freshDefaults() -> UserDefaults {
    let suite = "vizion.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  func testDefaults() {
    let store = UIStore(defaults: freshDefaults())
    XCTAssertEqual(store.theme, .system)
    XCTAssertEqual(store.activeMode, .clarify)
    XCTAssertEqual(store.targetModel, .opus5)
    XCTAssertFalse(store.autoTarget)
    XCTAssertEqual(store.autoPreference, .balanced)
    XCTAssertTrue(store.mediaStoreByDefault)
  }

  func testPersistsAndMigratesLegacyTargetIDs() throws {
    let defaults = freshDefaults()
    let legacy = """
      {"targetModel":"opus_4_8","thinkingLevels":{"gemini_3_5_thinking":"minimal","opus_4_8":"max","kimi_k2_6":"high"},
       "activeMode":"target","editorDraft":"hello","lengthByMode":{"expand":"long","polish":"short"}}
      """
    defaults.set(Data(legacy.utf8), forKey: UIStore.storageKey)
    let store = UIStore(defaults: defaults)
    XCTAssertEqual(store.targetModel, .opus5)
    XCTAssertEqual(store.activeMode, .target)
    XCTAssertEqual(store.editorDraft, "hello")
    XCTAssertEqual(store.thinkingLevels[.gemini36Flash], .minimal)
    XCTAssertEqual(store.thinkingLevels[.opus5], .max)
    XCTAssertNil(store.thinkingLevels[.kimiK3], "Kimi has no ladder — a stale level is dropped")
    XCTAssertEqual(store.lengthByMode[.expand], .long)
    XCTAssertNil(store.lengthByMode[.polish])

    store.editorDraft = "changed"
    store.saveNow()
    let reloaded = UIStore(defaults: defaults)
    XCTAssertEqual(reloaded.editorDraft, "changed")
  }

  func testHydrateHonoursStoredDefaultAndAccountSwitch() {
    let store = UIStore(defaults: freshDefaults())
    store.editorDraft = "user A's work"
    store.hydrate(profile: Profile(user_id: "a", default_model: "sonnet_5"), userID: "a")
    XCTAssertEqual(store.targetModel, .sonnet5)
    XCTAssertFalse(store.autoTarget)
    store.hydrate(profile: Profile(user_id: "b", default_model: nil), userID: "b")
    XCTAssertTrue(store.autoTarget)
    XCTAssertEqual(store.editorDraft, "", "another account on this device never inherits the draft")
  }

  func testThinkingLevelIsScopedToTheTargetLadder() {
    let store = UIStore(defaults: freshDefaults())
    store.targetModel = .gemini36Flash
    store.thinkingLevel = .minimal
    XCTAssertEqual(store.thinkingLevel, .minimal)
    store.targetModel = .opus5
    XCTAssertNil(store.thinkingLevel, "Gemini's minimal is not on the Anthropic ladder")
  }
}

@MainActor
final class EnhanceViewStoreTests: XCTestCase {
  func testViewPersistsPerAccountAndIsWipedOnSwitch() throws {
    let suite = "vizion.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let store = EnhanceViewStore(defaults: defaults)
    let result = EnhanceResult(
      output: "o", rationale: "r", diff: nil, tokenIn: 1, tokenOut: 1, modelUsed: "m", costUsd: 0,
      usage: EnhanceResult.Usage(todayCost: 0, capUsd: 2))
    store.set(EnhanceView(submitted: .init(input: "i", mode: .polish, target: .opus5), result: result), userID: "a")
    let reloaded = EnhanceViewStore(defaults: defaults)
    XCTAssertEqual(reloaded.view?.result.output, "o")
    reloaded.adopt(userID: "b")
    XCTAssertNil(reloaded.view)
  }

  func testEffectiveOutputAppliesPolishDecisions() {
    let diff = WordDiff.diffWords("teh cat", "the cat")
    let result = EnhanceResult(
      output: "the cat", rationale: "", diff: diff, tokenIn: 1, tokenOut: 1, modelUsed: "m", costUsd: 0,
      usage: EnhanceResult.Usage(todayCost: 0, capUsd: 2))
    var view = EnhanceView(submitted: .init(input: "teh cat", mode: .polish, target: .opus5), result: result)
    XCTAssertEqual(view.effectiveOutput, "the cat")
    view.rejected = [0]
    XCTAssertEqual(view.effectiveOutput, "teh cat")
  }
}
