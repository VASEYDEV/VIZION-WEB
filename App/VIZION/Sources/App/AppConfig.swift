import Foundation
import VizionCore

/// Build-time configuration, read from Info.plist keys that Xcode substitutes
/// from `Config/Secrets.xcconfig` (see `Config/Secrets.example.xcconfig`).
/// Fails CLOSED: with anything missing the app renders a "not configured"
/// screen instead of talking to the wrong project.
struct AppConfig: Sendable, Equatable {
  let supabaseURL: URL
  let supabaseAnonKey: String
  let apiBaseURL: URL

  enum Problem: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case invalidURL(String)

    var description: String {
      switch self {
      case let .missing(key):
        "\(key) is not set — copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill it in."
      case let .invalidURL(key):
        "\(key) is not a valid https URL."
      }
    }
  }

  static func load(from bundle: Bundle = .main) -> Result<AppConfig, Problem> {
    func value(_ key: String) -> Result<String, Problem> {
      guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return .failure(.missing(key)) }
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      // An unfilled template still carries the placeholder text.
      guard !trimmed.isEmpty, !trimmed.contains("YOUR-") else { return .failure(.missing(key)) }
      return .success(trimmed)
    }
    func url(_ key: String) -> Result<URL, Problem> {
      value(key).flatMap { raw in
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil else {
          return .failure(.invalidURL(key))
        }
        return .success(url)
      }
    }
    return url("SupabaseURL").flatMap { supabase in
      value("SupabaseAnonKey").flatMap { key in
        url("VizionAPIBaseURL").map { api in
          AppConfig(supabaseURL: supabase, supabaseAnonKey: key, apiBaseURL: api)
        }
      }
    }
  }
}
