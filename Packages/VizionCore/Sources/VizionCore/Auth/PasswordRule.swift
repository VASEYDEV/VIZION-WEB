import Foundation

/// The account password rule — one definition for the form and the copy that
/// tells the user what is expected (web: `auth/password.ts`). Supabase Auth
/// still owns the credential; this is input validation in front of it.
public enum PasswordRule {
  public static let minLength = 12

  public static let text =
    "At least \(minLength) characters, including a lowercase letter, an uppercase letter and a number."

  /// nil when acceptable, otherwise a sentence to show the user. NOT trimmed —
  /// leading/trailing spaces are legitimate password characters.
  public static func validate(_ password: String) -> String? {
    if password.count < minLength {
      return "Use at least \(minLength) characters."
    }
    var missing: [String] = []
    if !password.contains(where: \.isLowercase) {
      missing.append("a lowercase letter")
    }
    if !password.contains(where: \.isUppercase) {
      missing.append("an uppercase letter")
    }
    if !password.contains(where: \.isNumber) {
      missing.append("a number")
    }
    guard !missing.isEmpty else { return nil }
    let list = missing.count == 1
      ? missing[0]
      : "\(missing.dropLast().joined(separator: ", ")) and \(missing[missing.count - 1])"
    return "Add \(list)."
  }
}

/// `profiles.auth_method` — a Postgres enum label, so the raw values are frozen.
/// `apple` needs the companion migration (`docs/companion/0002-*.patch`):
/// without it the web's `handle_new_user()` files an Apple account under
/// `magic_link` — it still works, but goes through the set-password gate.
public enum AuthMethod: String, Codable, Sendable, Hashable {
  case magicLink = "magic_link"
  case github
  case google
  case apple

  public var connectionLabel: String {
    switch self {
    case .github: "Connected with GitHub"
    case .google: "Connected with Google"
    case .apple: "Connected with Apple"
    case .magicLink: "Signed in with email"
    }
  }
}

public enum Onboarding {
  /// Magic-link accounts must set a durable password at onboarding; OAuth
  /// accounts use the provider as their credential and are never gated.
  public static func needsPassword(authMethod: AuthMethod?, passwordSet: Bool) -> Bool {
    authMethod == .magicLink && !passwordSet
  }
}
