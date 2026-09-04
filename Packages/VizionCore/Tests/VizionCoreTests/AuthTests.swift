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
    // A known vector on a CONSTRUCTED nonce: what Apple receives is the
    // SHA-256 of the exact text Supabase is given. (Which bytes the stdlib
    // draws from a generator is its business and varies by Swift version —
    // asserting that would test the wrong thing.)
    XCTAssertEqual(
      SignInNonce(raw: String(repeating: "0", count: 64)).hashed,
      "60e05bd1b195af2f94112fa7197a5c88289058840ce7c6df9693756bc6250f55"
    )
    XCTAssertEqual(
      SignInNonce(raw: "abc").hashed,
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  func testSignInNonceDrawsEveryByteFromTheGivenGenerator() {
    var a = CountingGenerator()
    var b = CountingGenerator()
    XCTAssertEqual(
      SignInNonce.make(using: &a),
      SignInNonce.make(using: &b),
      "the same generator state must yield the same nonce"
    )
    var c = CountingGenerator(counter: 7)
    XCTAssertNotEqual(SignInNonce.make(using: &c), SignInNonce.make(using: &a))
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
