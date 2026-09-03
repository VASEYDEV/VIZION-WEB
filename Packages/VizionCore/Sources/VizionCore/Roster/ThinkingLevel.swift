import Foundation

/// The reasoning-depth ladder, weakest first (web: THINKING_LEVELS). One
/// app-wide vocabulary; each provider accepts a subset under its own parameter.
public enum ThinkingLevel: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case minimal
  case low
  case medium
  case high
  case xhigh
  case max

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .minimal: "Minimal"
    case .low: "Low"
    case .medium: "Medium"
    case .high: "High"
    case .xhigh: "Extra High"
    case .max: "Max"
    }
  }

  /// Hold-slider tone, keyed to the level's IDENTITY, never its ladder
  /// position — "high" wears the same steel on a 3-step ladder as a 5-step one.
  public var tone: DialTone {
    switch self {
    case .minimal, .low: .silver
    case .medium, .high: .steel
    case .xhigh, .max: .ultra
    }
  }
}

/// Fill-ramp tone for a dial stop. Sub-ultra is a monochrome silver
/// progression; only the ultra tier earns colour (web: dial-detents.ts).
public enum DialTone: String, Sendable, Hashable {
  case faint
  case silver
  case steel
  case ultra
}

/// One slider stop.
public struct Detent: Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let tone: DialTone

  public init(id: String, label: String, tone: DialTone) {
    self.id = id
    self.label = label
    self.tone = tone
  }

  /// Auto rides the slider as the LEFTMOST detent — dragging fully left is the
  /// one-gesture route back to "send nothing, provider default applies".
  public static let auto = Detent(id: "auto", label: "Auto", tone: .faint)
}

public enum ThinkingDial {
  /// `[Auto, ...ladder]` — the detent count adapts per model (4/5/6).
  public static func detents(for ladder: [ThinkingLevel]) -> [Detent] {
    [Detent.auto] + ladder.map { Detent(id: $0.rawValue, label: $0.label, tone: $0.tone) }
  }

  /// Caption under the capsule at the ladder's TOP stop — states the cost.
  public static let peakCaption = "Deepest reasoning — slowest, highest cost"
}

/// Auto-routing preferences — how Auto weighs strength against price (web:
/// AUTO_PREFERENCES). Wire vocabulary; the ladders live server-side.
public enum AutoPreference: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case quality
  case balanced
  case budget

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .quality: "Quality"
    case .balanced: "Balanced"
    case .budget: "Budget"
    }
  }

  public static let `default`: AutoPreference = .balanced

  public var tone: DialTone {
    switch self {
    case .budget: .silver
    case .balanced: .steel
    case .quality: .ultra
    }
  }

  /// The budget dial, cheapest first so the fill grows with spend.
  public static var detents: [Detent] {
    allCases.reversed().map { Detent(id: $0.rawValue, label: $0.label, tone: $0.tone) }
  }

  public static let peakCaption = "Strongest models — spends your cap faster"
}

/// Why Auto routed where it did (web: AutoRouteReason). Display-only; unknown
/// wire values render as nothing.
public enum AutoRouteReason: String, Codable, Sendable {
  case lightTask = "light-task"
  case heavyMode = "heavy-mode"
  case longInput = "long-input"
  case mediaContext = "media-context"

  public var label: String {
    switch self {
    case .lightTask: "quick task"
    case .heavyMode: "structural task"
    case .longInput: "long input"
    case .mediaContext: "visual context"
    }
  }

  public static func label(forRaw raw: String?) -> String? {
    guard let raw else { return nil }
    return AutoRouteReason(rawValue: raw)?.label
  }
}
