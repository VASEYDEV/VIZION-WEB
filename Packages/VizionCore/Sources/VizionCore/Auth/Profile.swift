import Foundation

public enum AppTheme: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case dark
  case light
  case system

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .dark: "Dark"
    case .light: "Light"
    case .system: "System"
    }
  }
}

/// The `profiles` row (web: database.types.ts Profile).
public struct Profile: Codable, Sendable, Hashable {
  public var user_id: String
  public var email: String?
  public var full_name: String?
  public var display_name: String?
  public var avatar_url: String?
  public var theme: AppTheme?
  /// nil = no stored default — the account starts on Auto.
  public var default_model: String?
  public var auth_method: AuthMethod?
  public var password_set: Bool?
  public var created_at: String?
  public var updated_at: String?

  public init(
    user_id: String, email: String? = nil, full_name: String? = nil, display_name: String? = nil,
    avatar_url: String? = nil, theme: AppTheme? = nil, default_model: String? = nil,
    auth_method: AuthMethod? = nil, password_set: Bool? = nil, created_at: String? = nil,
    updated_at: String? = nil
  ) {
    self.user_id = user_id
    self.email = email
    self.full_name = full_name
    self.display_name = display_name
    self.avatar_url = avatar_url
    self.theme = theme
    self.default_model = default_model
    self.auth_method = auth_method
    self.password_set = password_set
    self.created_at = created_at
    self.updated_at = updated_at
  }

  public var defaultTarget: TargetModel? { TargetModel.resolve(default_model) }
  public var needsPasswordOnboarding: Bool {
    Onboarding.needsPassword(authMethod: auth_method, passwordSet: password_set ?? false)
  }
}

/// `app_settings` row 1 — the owner console (web: owner/settings.ts).
public struct AppSettings: Codable, Sendable, Hashable {
  public var owner_user_id: String?
  public var open_access: Bool
  public var dev_accent_strength: Int

  public init(owner_user_id: String? = nil, open_access: Bool = true, dev_accent_strength: Int = 26) {
    self.owner_user_id = owner_user_id
    self.open_access = open_access
    self.dev_accent_strength = dev_accent_strength
  }

  /// Fail OPEN on availability: a missing settings row must never lock
  /// everyone out.
  public static let defaults = AppSettings()

  public static let devAccentRange = 0...60

  /// The recorded claimant is the owner. (The web also honours OWNER_EMAIL,
  /// which is server-side env — a native client cannot see it, so before the
  /// first claim the console is reachable only on the web.)
  public func isOwner(userID: String) -> Bool {
    owner_user_id == userID
  }
}
