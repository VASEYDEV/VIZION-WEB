import Foundation

/// The six enhancement modes (web: `src/lib/constants.ts` MODES + `modes.ts`
/// MODE_BLURB). Raw values are the wire ids AND the `enhance_mode` Postgres
/// enum labels — `target` keeps its id while its label is "Adapt".
///
/// Declaration order is display order: Polish sits beside Clarify because both
/// stay close to the author's original wording and shape.
public enum EnhanceMode: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case clarify
  case polish
  case expand
  case condense
  case reformat
  case target

  public var id: String {
    rawValue
  }

  /// The only sanctioned way to render a stored mode (ids and labels diverge).
  public var label: String {
    switch self {
    case .clarify: "Clarify"
    case .polish: "Polish"
    case .expand: "Expand"
    case .condense: "Condense"
    case .reformat: "Reformat"
    case .target: "Adapt"
    }
  }

  /// One-line description shown under the mode rig.
  public var blurb: String {
    switch self {
    case .polish: "Fixes spelling and grammar only; your wording stays intact."
    case .clarify: "Sharpens what you're asking for — same request, no ambiguity."
    case .expand: "Adds the detail, structure, and constraints your prompt is missing."
    case .condense: "Trims your prompt to the essentials without losing instructions."
    case .reformat: "Restructures your prompt into a shape you choose — JSON, steps, XML."
    case .target: "Adapts your prompt to the selected model's preferred style."
    }
  }

  /// Modes whose whole point is to keep the author's wording and shape; for
  /// these the destination affects routing/cost only, never formatting.
  public var isShapePreserving: Bool {
    self == .polish || self == .clarify
  }

  /// Modes that invent structure and route as "heavy" under Auto at any size
  /// (mirrors the server's HEAVY_ALWAYS — display-only here).
  public var isHeavy: Bool {
    switch self {
    case .expand, .reformat, .target: true
    case .polish, .clarify, .condense: false
    }
  }

  public static let `default`: EnhanceMode = .clarify

  /// Tolerant lookup for persisted values.
  public static func from(_ raw: String?) -> EnhanceMode? {
    guard let raw else { return nil }
    return EnhanceMode(rawValue: raw)
  }

  /// Display label for a raw stored id — falls back to the raw id so an
  /// unknown value still renders as something rather than blank.
  public static func label(forRaw raw: String?) -> String {
    guard let raw else { return "" }
    return EnhanceMode(rawValue: raw)?.label ?? raw
  }
}
