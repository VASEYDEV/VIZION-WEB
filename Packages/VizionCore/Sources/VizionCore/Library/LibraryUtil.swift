import Foundation

/// Pure helpers for the library (web: `util.ts`, `hash.ts`).
public enum LibraryUtil {
  /// Human relative time: "Now", "1 min ago", "Yesterday" — never "0m".
  public static func relativeTime(
    _ date: Date,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    let sec = Swift.max(0, Int(now.timeIntervalSince(date)))
    if sec < 45 {
      return "Now"
    }
    if sec < 3600 {
      return "\(Swift.max(1, sec / 60)) min ago"
    }
    if sec < 86400 {
      return "\(sec / 3600) hr ago"
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday) {
      return "Yesterday"
    }
    let day = sec / 86400
    if day < 7 {
      return "\(day) days ago"
    }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }

  /// Relative time from a raw PostgREST timestamp; the raw string when unparsable.
  public static func relativeTime(iso: String, now: Date = Date()) -> String {
    guard let date = PostgresDate.parse(iso) else { return iso }
    return relativeTime(date, now: now)
  }

  /// Derive a short, human title from a prompt's input text.
  public static func deriveTitle(_ input: String, max: Int = 60) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstLine = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    let base = firstLine.isEmpty ? trimmed : firstLine
    if base.isEmpty {
      return "Untitled prompt"
    }
    guard base.count > max else { return base }
    let head = String(base.prefix(max - 1))
    let trimmedHead = head.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    return "\(trimmedHead)…"
  }

  /// Normalise a free-form tag string into a clean, de-duplicated list.
  public static func parseTags(_ raw: String) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for part in raw.split(whereSeparator: { $0 == "," || $0.isNewline }) {
      var tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
      if tag.hasPrefix("#") {
        tag.removeFirst()
      }
      tag = tag.lowercased()
      if !tag.isEmpty, seen.insert(tag).inserted {
        out.append(tag)
      }
    }
    return out
  }

  /// Duplicate-detection content hash: sha256 over input ∥ US ∥ output ∥ US ∥
  /// mode ∥ US ∥ target, hex-encoded. MUST byte-match the server's SQL backfill.
  public static func contentHash(
    input: String,
    output: String,
    mode: String,
    target: String
  ) -> String {
    let joined = "\(input)\u{1F}\(output)\u{1F}\(mode)\u{1F}\(target)"
    return SHA256.hex(Array(joined.utf8))
  }

  /// Display-name rule: 3–24 chars, lowercase slug (or empty = unset).
  public static func isValidDisplayName(_ s: String) -> Bool {
    let value = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (3 ... 24).contains(value.count) else { return false }
    return value.allSatisfy { ch in
      ch.isASCII && (ch.isLowercase || ch.isNumber || ch == "_" || ch == "-")
    }
  }

  public static let displayNameRule =
    "Display names are 3–24 characters: lowercase letters, numbers, hyphen (-) or underscore (_)."
}
