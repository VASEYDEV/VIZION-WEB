import Foundation

/// URL intake (web: `draft-param.ts` + the auth callback route).
///
///   vizion://enhance?draft=…        Siri Shortcuts / share sheet prefill
///   vizion://library/<uuid>         open a saved prompt
///   vizion://auth/callback?code=…   Supabase OAuth / magic-link PKCE return
///
/// The same paths on the web origin (universal links) parse identically.
public enum DeepLink: Sendable, Hashable {
  case enhance(draft: String?)
  case library
  case prompt(id: String)
  case settings
  case authCallback(URL)
  /// A callback the provider answered with an error.
  case authError(String)

  public static let scheme = "vizion"

  public static func parse(_ url: URL) -> DeepLink? {
    let isScheme = url.scheme?.lowercased() == scheme
    let isWeb = url.scheme?.lowercased() == "https"
    guard isScheme || isWeb else { return nil }

    // vizion://host/path  vs  https://origin/host/path
    var segments = url.pathComponents.filter { $0 != "/" }
    if isScheme, let host = url.host {
      segments.insert(host, at: 0)
    }
    guard let first = segments.first else { return isScheme ? .enhance(draft: nil) : nil }

    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func param(_ name: String) -> String? {
      query.first { $0.name == name }?.value
    }

    switch first {
    case "enhance":
      return .enhance(draft: param("draft"))
    case "library":
      if segments.count >= 2, LibraryPaging.isUUID(segments[1]) {
        return .prompt(id: segments[1])
      }
      return .library
    case "profile", "settings":
      return .settings
    case "auth":
      guard segments.count >= 2, segments[1] == "callback" else { return nil }
      if let error = param("error_description") ?? param("error") {
        return .authError(error)
      }
      return .authCallback(url)
    default:
      return nil
    }
  }

  /// The redirect URL registered with Supabase Auth for this app.
  public static let authCallbackURL = URL(string: "\(scheme)://auth/callback")!
}

/// `?draft=` prefill rules — a URL is untrusted input arriving into a field
/// that may already hold real work.
public enum DraftParam {
  /// Longest prefill accepted. A silently truncated prompt is worse than a
  /// refused one.
  public static let maxChars = 8000

  public enum Outcome: Sendable, Hashable {
    /// Nothing to do — no param, or it was empty/oversized.
    case none
    /// Safe to apply directly: the editor was empty.
    case apply(String)
    /// The editor already holds work — ASK, never overwrite.
    case conflict(String)
  }

  public static func resolve(_ param: String?, currentDraft: String) -> Outcome {
    guard let param else { return .none }
    let text = param.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty || text.utf16.count > maxChars {
      return .none
    }
    return currentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .apply(text) : .conflict(text)
  }
}
