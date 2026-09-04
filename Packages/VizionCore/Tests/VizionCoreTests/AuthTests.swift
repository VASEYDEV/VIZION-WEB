@testable import VizionCore
import XCTest

final class AuthTests: XCTestCase {
  /// Yields the bytes 0, 1, 2 … so the nonce is a known vector.
  private struct CountingGenerator: RandomNumberGenerator {
    var counter: UInt8 = 0
    mutating func next() -> UInt64 {
      defer { counter &+= 1 }
      return UInt64(counter)
    }
  }

  func testSignInNonceIsSixtyFourHexCharacters() {
    let nonce = SignInNonce.make()
    XCTAssertEqual(nonce.raw.count, 64)
    XCTAssertTrue(nonce.raw.allSatisfy { "0123456789abcdef".contains($0) })
    XCTAssertEqual(nonce.hashed.count, 64)
    XCTAssertNotEqual(nonce, SignInNonce.make(), "two nonces must never collide")
  }

  func testSignInNonceHashIsSHA256OfTheRawText() {
    var generator = CountingGenerator()
    let nonce = SignInNonce.make(using: &generator)
    XCTAssertEqual(
      nonce.raw,
      "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    )
    XCTAssertEqual(
      nonce.hashed,
      "6c86c6aac5fb24bcf5d9939cb7d7d5645ce39418f449e03b262dd4fa14b4b92b"
    )
    XCTAssertEqual(
      SignInNonce(raw: String(repeating: "0", count: 64)).hashed,
      "60e05bd1b195af2f94112fa7197a5c88289058840ce7c6df9693756bc6250f55"
    )
  }

  func testAppleAccountsAreNeverPasswordGated() {
    XCTAssertFalse(Onboarding.needsPassword(authMethod: .apple, passwordSet: false))
    XCTAssertEqual(AuthMethod.apple.rawValue, "apple", "Postgres enum label — frozen")
    XCTAssertEqual(AuthMethod.apple.connectionLabel, "Connected with Apple")
    XCTAssertEqual(
      try JSONDecoder().decode([AuthMethod].self, from: Data(#"["magic_link","apple"]"#.utf8)),
      [.magicLink, .apple]
    )
  }
}
