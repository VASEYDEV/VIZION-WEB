import Foundation

/// The nonce Sign in with Apple requires. The RAW value goes to Supabase with
/// the identity token; its SHA-256 (hex) goes into Apple's request. Apple
/// copies the hash into the token's `nonce` claim, Supabase hashes the raw
/// value and compares, so a token minted for one request cannot be replayed
/// into another sign-in.
public struct SignInNonce: Sendable, Equatable {
  public let raw: String

  public init(raw: String) {
    self.raw = raw
  }

  /// SHA-256 of the raw value, lowercase hex — what the Apple request carries.
  public var hashed: String {
    SHA256.hex(Array(raw.utf8))
  }

  /// 32 random bytes as 64 lowercase hex characters.
  public static func make(using generator: inout some RandomNumberGenerator) -> SignInNonce {
    var bytes = [UInt8](repeating: 0, count: 32)
    for index in bytes.indices {
      bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
    }
    return SignInNonce(raw: bytes.map { String(format: "%02x", $0) }.joined())
  }

  /// From the system's cryptographic generator (`arc4random_buf` on Apple platforms).
  public static func make() -> SignInNonce {
    var generator = SystemRandomNumberGenerator()
    return make(using: &generator)
  }
}
