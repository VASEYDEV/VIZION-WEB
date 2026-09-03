import XCTest
@testable import VIZION

final class AppConfigTests: XCTestCase {
  func testTemplatePlaceholdersFailClosed() {
    // The test bundle carries no Info.plist keys → a clear "missing" problem,
    // never a client pointed at nothing.
    switch AppConfig.load(from: Bundle(for: AppConfigTests.self)) {
    case .success: XCTFail("a bundle without config must not load")
    case let .failure(problem): XCTAssertTrue(problem.description.contains("SupabaseURL"))
    }
  }
}
