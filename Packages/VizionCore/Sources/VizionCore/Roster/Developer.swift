import Foundation

/// Model developers in locked display order: Anthropic and OpenAI first, the
/// rest alphabetical (web: DEVELOPER_ORDER / DEVELOPER_LABEL).
public enum Developer: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case anthropic
  case openai
  case deepseek
  case google
  case meta
  case minimax
  case mistral
  case moonshot
  case perplexity
  case qwen
  case xai
  case zai

  public var id: String {
    rawValue
  }

  public var label: String {
    switch self {
    case .anthropic: "Anthropic"
    case .openai: "OpenAI"
    case .deepseek: "DeepSeek"
    case .google: "Google"
    case .meta: "Meta AI"
    case .minimax: "MiniMax"
    case .mistral: "Mistral"
    case .moonshot: "Moonshot AI"
    case .perplexity: "Perplexity"
    case .qwen: "Qwen"
    case .xai: "xAI"
    case .zai: "Z.ai"
    }
  }

  /// Per-developer identity accent (web: `dev-accents.css`). ONE hex per
  /// developer in both themes — the values were derived to sit between the
  /// dark and light card fills, so a light override would break the property.
  /// Library-list scope only (see ADR-0003 in the web repo).
  public var accentHex: String {
    switch self {
    case .anthropic: "#A77159"
    case .openai: "#9C595D"
    case .deepseek: "#798AEE"
    case .google: "#219042"
    case .meta: "#3B7ED6"
    case .minimax: "#C85975"
    case .mistral: "#DA772A"
    case .moonshot: "#0088AF"
    case .perplexity: "#00A0B3"
    case .qwen: "#826ED4"
    case .xai: "#7D858E"
    case .zai: "#1598E3"
    }
  }
}
