import Foundation

/// Reference-role context blocks the composer sends beside the enhance
/// request (web: `media/context.ts`). Pure builders.
public struct MediaContextItem: Sendable, Hashable {
  public var role: AttachmentRole
  public var isReady: Bool
  public var name: String
  public var description: String?
  public var attrs: MediaAttributes?

  public init(
    role: AttachmentRole,
    isReady: Bool,
    name: String,
    description: String?,
    attrs: MediaAttributes?
  ) {
    self.role = role
    self.isReady = isReady
    self.name = name
    self.description = description
    self.attrs = attrs
  }
}

public enum MediaContext {
  public static let maxItems = 4
  public static let maxChars = 1500

  /// Display-safe file name: control characters stripped, middle-ellipsized.
  public static func sanitizeName(_ name: String, max: Int = 40) -> String {
    let cleaned = name.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
      .map { String($0) }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    let clean = cleaned.isEmpty ? "untitled" : cleaned
    guard clean.count > max else { return clean }
    let headCount = Int((Double(max - 1) / 2).rounded(.up))
    let tailCount = (max - 1) / 2
    return "\(clean.prefix(headCount))…\(clean.suffix(tailCount))"
  }

  /// Fallback summary when only on-device attributes exist (no model prose).
  static func summarize(_ attrs: MediaAttributes?) -> String? {
    guard let attrs else { return nil }
    var bits: [String] = []
    if let s = attrs.subject {
      bits.append(s)
    }
    if let s = attrs.style {
      bits.append("\(s) style")
    }
    if let m = attrs.mood {
      bits.append("\(m) mood")
    }
    if let p = attrs.palette,
       !p.isEmpty {
      bits.append("palette \(p.prefix(4).joined(separator: " "))")
    }
    if let w = attrs.width, let h = attrs.height {
      bits.append("\(w)×\(h)")
    }
    if let d = attrs.durationSec {
      bits.append("~\(Int(d.rounded()))s")
    }
    return bits.isEmpty ? nil : bits.joined(separator: ", ")
  }

  /// One line per READY reference-role attachment that has something to say,
  /// capped at `maxItems` items of `maxChars` each.
  public static func build(_ items: [MediaContextItem]) -> [String] {
    var blocks: [String] = []
    for item in items {
      guard item.role == .reference, item.isReady else { continue }
      let described = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)
      let body = (described?.isEmpty == false ? described : nil) ?? summarize(item.attrs)
      guard let body else { continue }
      let line = "Visual reference (\(sanitizeName(item.name, max: 60))): \(body)"
      blocks.append(String(line.prefix(maxChars)))
      if blocks.count >= maxItems {
        break
      }
    }
    return blocks
  }

  /// One-line style snippet (the "Style reference" role's insert action).
  public static func styleSnippet(_ attrs: MediaAttributes) -> String {
    var bits: [String] = []
    if let s = attrs.style {
      bits.append(s)
    }
    if let l = attrs.lighting {
      bits.append("\(l) lighting")
    }
    if let m = attrs.mood {
      bits.append("\(m) mood")
    }
    if let p = attrs.palette,
       !p.isEmpty {
      bits.append("palette \(p.prefix(6).joined(separator: " "))")
    }
    let body = bits.isEmpty
      ? (attrs.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
      : bits.joined(separator: "; ")
    return body.isEmpty ? "" : "Style reference: \(body)"
  }
}
