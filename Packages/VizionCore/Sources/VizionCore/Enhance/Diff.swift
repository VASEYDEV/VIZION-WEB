import Foundation

/// Word-level transformation diff (web: `diff.ts`) — the brand's signature
/// gesture. Pure and deterministic. Produces a flat list of segments tagged
/// equal / added / removed; the UI lights "added" in Laser on the output side
/// and dims "removed" on the input side.
public enum WordDiff {
  /// Per-side token budget for interactive diffs (the LCS table is O(n·m)).
  public static let tokenBudget = 2_000

  /// Split into tokens keeping whitespace runs as their own tokens, so the
  /// diff re-joins losslessly (JS: `/\s+|[^\s]+/g`).
  public static func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var currentIsSpace: Bool?
    for ch in text {
      let isSpace = ch.isWhitespace
      if let was = currentIsSpace, was != isSpace {
        tokens.append(current)
        current = ""
      }
      current.append(ch)
      currentIsSpace = isSpace
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
  }

  /// LCS diff over word tokens, removed tokens interleaved at their original
  /// position, adjacent same-op runs merged.
  public static func diffWords(_ before: String, _ after: String) -> [DiffSegment] {
    let a = tokenize(before)
    let b = tokenize(after)
    let n = a.count
    let m = b.count
    let width = m + 1
    var lcs = [Int32](repeating: 0, count: (n + 1) * width)
    if n > 0, m > 0 {
      for i in stride(from: n - 1, through: 0, by: -1) {
        for j in stride(from: m - 1, through: 0, by: -1) {
          let idx = i * width + j
          if a[i] == b[j] {
            lcs[idx] = lcs[(i + 1) * width + j + 1] + 1
          } else {
            lcs[idx] = Swift.max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
          }
        }
      }
    }

    var raw: [DiffSegment] = []
    var i = 0
    var j = 0
    while i < n, j < m {
      if a[i] == b[j] {
        raw.append(DiffSegment(op: .equal, text: a[i]))
        i += 1
        j += 1
      } else if lcs[(i + 1) * width + j] >= lcs[i * width + j + 1] {
        raw.append(DiffSegment(op: .removed, text: a[i]))
        i += 1
      } else {
        raw.append(DiffSegment(op: .added, text: b[j]))
        j += 1
      }
    }
    while i < n {
      raw.append(DiffSegment(op: .removed, text: a[i]))
      i += 1
    }
    while j < m {
      raw.append(DiffSegment(op: .added, text: b[j]))
      j += 1
    }
    return mergeAdjacent(raw)
  }

  /// diffWords with a hard size bound — nil (show plain text + a note)
  /// instead of freezing the main thread.
  public static func boundedDiffWords(
    _ before: String, _ after: String, budget: Int = tokenBudget
  ) -> [DiffSegment]? {
    if tokenize(before).count > budget || tokenize(after).count > budget { return nil }
    return diffWords(before, after)
  }

  static func mergeAdjacent(_ segments: [DiffSegment]) -> [DiffSegment] {
    var out: [DiffSegment] = []
    for seg in segments {
      if let last = out.last, last.op == seg.op {
        out[out.count - 1].text += seg.text
      } else {
        out.append(seg)
      }
    }
    return out
  }

  /// One reviewable change: a maximal run of non-equal segments (whitespace-
  /// only equal segments between them bridge the run).
  public struct Hunk: Sendable, Hashable, Identifiable {
    public let index: Int
    public var removed: String
    public var added: String
    public var id: Int { index }
  }

  /// Hunk id per segment (nil = equal text outside any hunk). The single
  /// grouping rule `hunks` and `applyDecisions` share.
  public static func assignHunks(_ segments: [DiffSegment]) -> [Int?] {
    var ids = [Int?](repeating: nil, count: segments.count)
    var nextID = 0
    var activeID: Int?
    var pendingWhitespace: [Int] = []
    for (i, seg) in segments.enumerated() {
      if seg.op == .equal {
        if seg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, activeID != nil {
          pendingWhitespace.append(i)
        } else {
          activeID = nil
          pendingWhitespace = []
        }
        continue
      }
      if let active = activeID {
        for w in pendingWhitespace { ids[w] = active }
        pendingWhitespace = []
        ids[i] = active
      } else {
        activeID = nextID
        nextID += 1
        pendingWhitespace = []
        ids[i] = activeID
      }
    }
    return ids
  }

  /// Group a diff into reviewable hunks (the per-change accept/reject model).
  public static func hunks(_ segments: [DiffSegment]) -> [Hunk] {
    let ids = assignHunks(segments)
    var hunks: [Int: Hunk] = [:]
    for (i, seg) in segments.enumerated() {
      guard let id = ids[i] else { continue }
      var hunk = hunks[id] ?? Hunk(index: id, removed: "", added: "")
      if seg.op != .added { hunk.removed += seg.text }
      if seg.op != .removed { hunk.added += seg.text }
      hunks[id] = hunk
    }
    return hunks.keys.sorted().compactMap { hunks[$0] }
  }

  /// Rebuild output applying per-hunk decisions: a rejected hunk keeps the
  /// INPUT side, a kept hunk the OUTPUT side; equal text always survives.
  public static func applyDecisions(_ segments: [DiffSegment], rejected: Set<Int>) -> String {
    let ids = assignHunks(segments)
    var out = ""
    for (i, seg) in segments.enumerated() {
      if seg.op == .equal {
        out += seg.text
        continue
      }
      let isRejected = ids[i].map { rejected.contains($0) } ?? false
      if seg.op == .added, !isRejected { out += seg.text }
      if seg.op == .removed, isRejected { out += seg.text }
    }
    return out
  }

  /// Count of changed SECTIONS — a replaced phrase (removed+added) counts once;
  /// whitespace bridges don't break a run; whitespace-only runs don't count.
  public static func countChangedSections(_ segments: [DiffSegment]) -> Int {
    var sections = 0
    var inRun = false
    var runHasInk = false
    for seg in segments {
      if seg.op == .equal {
        if seg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        if inRun, runHasInk { sections += 1 }
        inRun = false
        runHasInk = false
      } else {
        inRun = true
        if !seg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { runHasInk = true }
      }
    }
    if inRun, runHasInk { sections += 1 }
    return sections
  }

  /// The diff's input side reconstructed (= the author's original, or the
  /// previous result on a refine run).
  public static func inputSide(_ segments: [DiffSegment]) -> String {
    segments.filter { $0.op != .added }.map(\.text).joined()
  }
}
