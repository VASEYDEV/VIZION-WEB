import Foundation

/// Library filter + keyset cursor plumbing (web: `paging.ts`). Pure.
public enum LibraryView: String, CaseIterable, Codable, Sendable, Identifiable {
  case all
  case favorites
  case archived
  /// Recently deleted — the durable recovery surface for soft deletes.
  case trash
  /// A different relation (`drafts`), living in this union so the view switch,
  /// filter badge and back button all keep working through it.
  case drafts

  public var id: String {
    rawValue
  }

  public var label: String {
    switch self {
    case .all: "All"
    case .favorites: "Favorites"
    case .archived: "Archived"
    case .trash: "Recently deleted"
    case .drafts: "Drafts"
    }
  }
}

public enum LibrarySort: String, CaseIterable, Codable, Sendable, Identifiable {
  case updated
  case created
  case title

  public var id: String {
    rawValue
  }

  public var label: String {
    switch self {
    case .updated: "Recently updated"
    case .created: "Recently created"
    case .title: "Title"
    }
  }

  public var column: String {
    switch self {
    case .updated: "updated_at"
    case .created: "created_at"
    case .title: "title"
    }
  }

  public var ascending: Bool {
    self == .title
  }
}

public struct LibraryFilter: Sendable, Hashable, Codable {
  /// Title search (ilike; drafts also search the body).
  public var q: String?
  public var model: TargetModel?
  public var mode: EnhanceMode?
  public var tag: String?
  /// Collection id (uuid). Only the SHAPE is validated — an unknown id matches nothing.
  public var collection: String?
  public var view: LibraryView
  public var sort: LibrarySort

  public init(
    q: String? = nil, model: TargetModel? = nil, mode: EnhanceMode? = nil, tag: String? = nil,
    collection: String? = nil, view: LibraryView = .all, sort: LibrarySort = .updated
  ) {
    self.q = q?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      .map { String($0.prefix(200)) }
    self.model = model
    self.mode = mode
    self.tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      .map { String($0.prefix(60)) }
    self.collection = collection.flatMap { LibraryPaging.isUUID($0) ? $0 : nil }
    self.view = view
    self.sort = sort
  }

  public static let `default` = LibraryFilter()

  public var isDraftsView: Bool {
    view == .drafts
  }

  /// Count of narrowing selections — the filter button's badge. Search is
  /// excluded (it's visible in the field itself).
  public var activeCount: Int {
    var n = 0
    if model != nil {
      n += 1
    }
    if mode != nil {
      n += 1
    }
    if tag != nil {
      n += 1
    }
    if collection != nil {
      n += 1
    }
    if view != .all {
      n += 1
    }
    if sort != .updated {
      n += 1
    }
    return n
  }

  public var isDefault: Bool {
    activeCount == 0 && q == nil
  }

  /// The web URL for this filter (defaults omitted) — used for Share/hand-off.
  public func webPath() -> String {
    var params: [(String, String)] = []
    if let q {
      params.append(("q", q))
    }
    if let model {
      params.append(("model", model.rawValue))
    }
    if let mode {
      params.append(("mode", mode.rawValue))
    }
    if let tag {
      params.append(("tag", tag))
    }
    if let collection {
      params.append(("collection", collection))
    }
    if view != .all {
      params.append(("view", view.rawValue))
    }
    if sort != .updated {
      params.append(("sort", sort.rawValue))
    }
    guard !params.isEmpty else { return "/library" }
    var components = URLComponents()
    components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
    return "/library?\(components.percentEncodedQuery ?? "")"
  }
}

public enum LibraryPaging {
  public static let pageSize = 30
  static let cursorSeparator = "\u{1F}"

  /// Escape ilike wildcards so a literal % or _ matches itself.
  public static func escapeLike(_ s: String) -> String {
    var out = ""
    for ch in s {
      if ch == "\\" || ch == "%" || ch == "_" {
        out.append("\\")
      }
      out.append(ch)
    }
    return out
  }

  /// Quote a value for a PostgREST `or=()` expression.
  public static func quoteOrValue(_ v: String) -> String {
    let escaped = v.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  /// Keyset cursor: the sort column's value + the row id (stable tiebreak).
  public static func encodeCursor(value: String, id: String) -> String {
    "\(value)\(cursorSeparator)\(id)"
  }

  /// nil for a tampered/garbled cursor → fresh first page. The id half is
  /// pinned to a UUID because both halves are interpolated into filter grammar.
  public static func decodeCursor(_ raw: String) -> (value: String, id: String)? {
    guard let sep = raw.range(of: cursorSeparator),
          sep.lowerBound != raw.startIndex else { return nil }
    let value = String(raw[..<sep.lowerBound])
    let id = String(raw[sep.upperBound...])
    guard !id.isEmpty, isUUID(id) else { return nil }
    return (value, id)
  }

  /// The PostgREST `.or()` expression for the next page after a cursor.
  public static func cursorExpression(
    sort: LibrarySort,
    cursor: (value: String, id: String)
  ) -> String {
    let op = sort.ascending ? "gt" : "lt"
    let v = quoteOrValue(cursor.value)
    return "\(sort.column).\(op).\(v),and(\(sort.column).eq.\(v),id.lt.\(cursor.id))"
  }

  /// The drafts page is always (updated_at desc, id desc).
  public static func draftsCursorExpression(cursor: (value: String, id: String)) -> String {
    let v = quoteOrValue(cursor.value)
    return "updated_at.lt.\(v),and(updated_at.eq.\(v),id.lt.\(cursor.id))"
  }

  /// `title.ilike.%q%,body.ilike.%q%` — drafts search covers the body too.
  public static func draftsSearchExpression(_ q: String) -> String {
    let like = "%\(escapeLike(q))%"
    return "title.ilike.\(quoteOrValue(like)),body.ilike.\(quoteOrValue(like))"
  }

  public static func isUUID(_ s: String) -> Bool {
    let parts = s.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 5 else { return false }
    let lengths = [8, 4, 4, 4, 12]
    for (part, len) in zip(parts, lengths) {
      guard part.count == len, part.allSatisfy(\.isHexDigit) else { return false }
    }
    return true
  }
}

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
