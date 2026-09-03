import Foundation

/// Tolerant parser for the timestamps PostgREST returns
/// (`2026-08-15T11:30:00.123456+00:00`, `…Z`, `…+00`, or a space separator).
/// `ISO8601DateFormatter` is strict about fractional-second digits, and
/// Postgres emits microseconds, so this is done by hand.
public enum PostgresDate {
  public static func parse(_ raw: String) -> Date? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    let scalars = Array(s.utf8)
    guard scalars.count >= 19 else { return nil }

    func num(_ from: Int, _ len: Int) -> Int? {
      guard from + len <= scalars.count else { return nil }
      var value = 0
      for i in from..<(from + len) {
        let c = scalars[i]
        guard c >= 48, c <= 57 else { return nil }
        value = value * 10 + Int(c - 48)
      }
      return value
    }

    guard let year = num(0, 4), scalars[4] == 45, let month = num(5, 2), scalars[7] == 45,
      let day = num(8, 2), scalars[10] == 84 || scalars[10] == 32, let hour = num(11, 2),
      scalars[13] == 58, let minute = num(14, 2), scalars[16] == 58, let second = num(17, 2)
    else { return nil }
    guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
      (0...59).contains(minute), (0...60).contains(second)
    else { return nil }

    var index = 19
    var nanos = 0
    if index < scalars.count, scalars[index] == 46 {
      index += 1
      var digits = 0
      var fraction = 0
      while index < scalars.count, scalars[index] >= 48, scalars[index] <= 57 {
        if digits < 9 {
          fraction = fraction * 10 + Int(scalars[index] - 48)
          digits += 1
        }
        index += 1
      }
      while digits < 9 {
        fraction *= 10
        digits += 1
      }
      nanos = fraction
    }

    var offsetSeconds = 0
    if index < scalars.count {
      let c = scalars[index]
      if c == 90 {
        index += 1
      } else if c == 43 || c == 45 {
        let sign = c == 43 ? 1 : -1
        guard let oh = num(index + 1, 2) else { return nil }
        var om = 0
        var next = index + 3
        if next < scalars.count, scalars[next] == 58 { next += 1 }
        if let m = num(next, 2) { om = m }
        offsetSeconds = sign * (oh * 3600 + om * 60)
      }
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    components.nanosecond = nanos
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    guard let utc = calendar.date(from: components) else { return nil }
    // A day that does not exist in its month (Feb 30) rolls over silently —
    // read the components back and refuse anything that moved.
    let check = calendar.dateComponents([.year, .month, .day], from: utc)
    guard check.year == year, check.month == month, check.day == day else { return nil }
    return utc.addingTimeInterval(TimeInterval(-offsetSeconds))
  }

  /// ISO-8601 with fractional seconds in UTC — the shape the server accepts
  /// for `updated_at` writes and the drafts optimistic-concurrency predicate.
  public static func format(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}
