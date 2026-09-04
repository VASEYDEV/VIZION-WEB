import Foundation

/// How far Condense and Expand should go (web: `lengths.ts`). The dial is
/// shared but the LABELS are per mode, because the same position means opposite
/// things: the aggressive end of Condense is the smallest output, the
/// aggressive end of Expand is the largest.
public enum LengthSetting: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case short
  case medium
  case long

  public var id: String {
    rawValue
  }

  /// Label for a mode, or nil when the mode has no dial.
  public func label(for mode: EnhanceMode) -> String? {
    switch mode {
    case .condense:
      switch self {
      case .short: "Tight"
      case .medium: "Balanced"
      case .long: "Essential"
      }
    case .expand:
      switch self {
      case .short: "Focused"
      case .medium: "Thorough"
      case .long: "Comprehensive"
      }
    default: nil
    }
  }
}

public extension EnhanceMode {
  /// Whether the length dial applies to this mode.
  var hasLengthControl: Bool {
    self == .condense || self == .expand
  }

  /// Ordered least → most aggressive *for this mode*, or nil when it has no dial.
  var lengthOptions: [(id: LengthSetting, label: String)]? {
    guard hasLengthControl else { return nil }
    return LengthSetting.allCases.compactMap { setting in
      setting.label(for: self).map { (setting, $0) }
    }
  }
}
