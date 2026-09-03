import Foundation

/// Generation-syntax formatters (web: `media/formatters.ts`): fold a reference
/// into a generation-ready prompt in the target engine's idiom.
public enum GenerationPrompt {
  public static func build(base: String, attrs: MediaAttributes, target: GenTarget) -> String {
    switch target {
    case .midjourney: midjourney(base, attrs)
    case .audio: audioSpec(base, attrs)
    case .runway, .sora, .kling: motion(base, attrs, engine: target.rawValue)
    }
  }

  /// Common Midjourney aspect ratios; extracted dimensions snap to the nearest.
  static let midjourneyRatios: [(Int, Int)] = [
    (1, 1), (4, 3), (3, 4), (3, 2), (2, 3), (16, 9), (9, 16), (5, 4), (4, 5), (21, 9),
  ]

  public static func nearestAspect(width: Int, height: Int) -> String {
    let r = Double(width) / Double(height)
    var best = midjourneyRatios[0]
    var bestDiff = Double.infinity
    for ratio in midjourneyRatios {
      let diff = abs(Double(ratio.0) / Double(ratio.1) - r)
      if diff < bestDiff {
        bestDiff = diff
        best = ratio
      }
    }
    return "\(best.0):\(best.1)"
  }

  static func midjourney(_ base: String, _ a: MediaAttributes) -> String {
    var parts: [String] = []
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { parts.append(trimmed) }
    if let s = a.subject, !s.isEmpty { parts.append(s) }
    if let c = a.composition, !c.isEmpty { parts.append(c) }
    if let l = a.lighting, !l.isEmpty { parts.append("\(l) lighting") }
    if let s = a.style, !s.isEmpty { parts.append("\(s) style") }
    if let m = a.mood, !m.isEmpty { parts.append("\(m) mood") }
    if let p = a.palette, !p.isEmpty { parts.append("palette \(p.joined(separator: " "))") }
    let ar: String
    if let w = a.width, let h = a.height, w > 0, h > 0 {
      ar = nearestAspect(width: w, height: h)
    } else {
      ar = "16:9"
    }
    return "\(parts.joined(separator: ", ")) --ar \(ar) --v 6".trimmingCharacters(in: .whitespaces)
  }

  static func motion(_ base: String, _ a: MediaAttributes, engine: String) -> String {
    var lines: [String] = []
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { lines.append(trimmed) }
    if let s = a.subject, !s.isEmpty { lines.append("Subject: \(s).") }
    if let c = a.composition, !c.isEmpty { lines.append("Camera & motion: \(c).") }
    if let l = a.lighting, !l.isEmpty { lines.append("Lighting: \(l).") }
    if let s = a.style, !s.isEmpty { lines.append("Style: \(s).") }
    if let m = a.mood, !m.isEmpty { lines.append("Mood: \(m).") }
    if let p = a.palette, !p.isEmpty { lines.append("Palette: \(p.joined(separator: ", ")).") }
    return "[\(engine)] \(lines.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
  }

  static func audioSpec(_ base: String, _ a: MediaAttributes) -> String {
    var lines: [String] = []
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { lines.append(trimmed) }
    if let m = a.mood, !m.isEmpty { lines.append("Mood: \(m).") }
    if let d = a.durationSec { lines.append("Duration: ~\(Int(d.rounded()))s.") }
    return lines.joined(separator: " ")
  }
}

/// Per-user media storage budget; Amber warning at 80%.
public enum MediaBudget {
  public static let quotaBytes = 50 * 1024 * 1024

  public struct Status: Sendable, Hashable {
    public var usedBytes: Int
    public var quotaBytes: Int
    public var fraction: Double
    public var warn: Bool
    public var over: Bool
  }

  public static func status(usedBytes: Int, quotaBytes: Int = quotaBytes) -> Status {
    let fraction = quotaBytes > 0 ? Double(usedBytes) / Double(quotaBytes) : 1
    return Status(
      usedBytes: usedBytes, quotaBytes: quotaBytes, fraction: fraction, warn: fraction >= 0.8,
      over: fraction >= 1
    )
  }

  public static func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) KB" }
    return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
  }

  public static let quotaMessage =
    "Storage full — remove media in Settings → Data & privacy to continue."
}
