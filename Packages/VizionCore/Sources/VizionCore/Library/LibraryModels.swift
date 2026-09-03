import Foundation

/// One library card — everything the list renders, no version bodies (web:
/// PromptCard). Timestamps are kept as the RAW PostgREST strings because the
/// keyset cursor must reproduce them byte-for-byte.
public struct PromptCard: Sendable, Hashable, Identifiable {
  public var id: String
  public var title: String
  public var targetModel: String
  public var tags: [String]
  public var createdAt: String
  public var updatedAt: String
  public var favorite: Bool
  public var archived: Bool
  /// Soft-deleted (in Recently deleted).
  public var deleted: Bool
  public var preview: String?
  public var mode: String?
  public var versions: Int
  public var collectionID: String?

  public init(
    id: String, title: String, targetModel: String, tags: [String], createdAt: String,
    updatedAt: String, favorite: Bool, archived: Bool, deleted: Bool, preview: String?,
    mode: String?, versions: Int, collectionID: String?
  ) {
    self.id = id
    self.title = title
    self.targetModel = targetModel
    self.tags = tags
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.favorite = favorite
    self.archived = archived
    self.deleted = deleted
    self.preview = preview
    self.mode = mode
    self.versions = versions
    self.collectionID = collectionID
  }

  public var target: TargetModel? { TargetModel.resolve(targetModel) }
  public var modelLabel: String { TargetModel.label(forRaw: targetModel) }
  public var developer: Developer? { TargetModel.developer(forRaw: targetModel) }
  public var modeLabel: String? { mode.map(EnhanceMode.label(forRaw:)) }
  public var updatedDate: Date? { PostgresDate.parse(updatedAt) }
  public var createdDate: Date? { PostgresDate.parse(createdAt) }
}

/// The raw `prompts` row shape the page query selects (Codable for PostgREST).
public struct PromptPageRow: Codable, Sendable, Hashable {
  public struct Count: Codable, Sendable, Hashable {
    public var count: Int
  }

  public var id: String
  public var title: String
  public var target_model: String
  public var tags: [String]
  public var created_at: String
  public var updated_at: String
  public var favorite: Bool
  public var archived_at: String?
  public var deleted_at: String?
  public var preview: String?
  public var current_mode: String?
  public var collection_id: String?
  public var prompt_versions: [Count]?

  public var card: PromptCard {
    PromptCard(
      id: id, title: title, targetModel: target_model, tags: tags, createdAt: created_at,
      updatedAt: updated_at, favorite: favorite, archived: archived_at != nil,
      deleted: deleted_at != nil, preview: preview, mode: current_mode,
      versions: prompt_versions?.first?.count ?? 1, collectionID: collection_id
    )
  }
}

public struct CollectionFacet: Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var count: Int

  public init(id: String, name: String, count: Int) {
    self.id = id
    self.name = name
    self.count = count
  }
}

public struct ModelFacet: Sendable, Hashable, Identifiable {
  public var id: String
  public var count: Int

  public init(id: String, count: Int) {
    self.id = id
    self.count = count
  }

  public var label: String { TargetModel.label(forRaw: id) }
  public var developer: Developer? { TargetModel.developer(forRaw: id) }
}

/// Facets for the filter sheet: ONLY the models actually present, never the
/// full roster (web: LibraryFacets).
public struct LibraryFacets: Sendable, Hashable {
  public var models: [ModelFacet]
  public var tags: [String]
  public var collections: [CollectionFacet]

  public init(models: [ModelFacet], tags: [String], collections: [CollectionFacet]) {
    self.models = models
    self.tags = tags
    self.collections = collections
  }

  public static let empty = LibraryFacets(models: [], tags: [], collections: [])

  /// Reduce a capped column-only select into facets (PostgREST aggregates are
  /// disabled on the hosted project, so counting happens client-side).
  public static func reduce(
    rows: [(targetModel: String, tags: [String], collectionID: String?)],
    collections: [(id: String, name: String)]
  ) -> LibraryFacets {
    var counts: [String: Int] = [:]
    var tagSet = Set<String>()
    var collectionCounts: [String: Int] = [:]
    for row in rows {
      counts[row.targetModel, default: 0] += 1
      tagSet.formUnion(row.tags)
      if let c = row.collectionID { collectionCounts[c, default: 0] += 1 }
    }
    let models = counts.map { ModelFacet(id: $0.key, count: $0.value) }
      .sorted { a, b in a.count != b.count ? a.count > b.count : a.id < b.id }
    return LibraryFacets(
      models: models,
      tags: tagSet.sorted(),
      collections: collections.map {
        CollectionFacet(id: $0.id, name: $0.name, count: collectionCounts[$0.id] ?? 0)
      }
    )
  }

  public struct FacetGroup: Sendable, Hashable {
    /// nil for ids no longer in the roster — the "Other" group, last.
    public var developer: Developer?
    public var label: String
    public var models: [ModelFacet]
  }

  /// Group model facets under developer headers, or nil when grouping would
  /// add nothing (a single-developer library keeps the flat chip row).
  public static func groupModels(_ models: [ModelFacet]) -> [FacetGroup]? {
    var byDeveloper: [Developer: [ModelFacet]] = [:]
    var orphans: [ModelFacet] = []
    for m in models {
      if let d = m.developer { byDeveloper[d, default: []].append(m) } else { orphans.append(m) }
    }
    var groups: [FacetGroup] = []
    for developer in Developer.allCases {
      if let bucket = byDeveloper[developer] {
        groups.append(FacetGroup(developer: developer, label: developer.label, models: bucket))
      }
    }
    if !orphans.isEmpty { groups.append(FacetGroup(developer: nil, label: "Other", models: orphans)) }
    return groups.count > 1 ? groups : nil
  }
}

/// One Drafts-list row (web: DraftCard). Bodies are NOT fetched for the list.
public struct DraftCard: Sendable, Hashable, Identifiable {
  public static let previewChars = 160

  public var id: String
  public var title: String
  public var preview: String
  public var targetModel: String
  public var mode: String
  public var thinkingLevel: String?
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String, title: String, preview: String, targetModel: String, mode: String,
    thinkingLevel: String?, createdAt: String, updatedAt: String
  ) {
    self.id = id
    self.title = title
    self.preview = preview
    self.targetModel = targetModel
    self.mode = mode
    self.thinkingLevel = thinkingLevel
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var modelLabel: String { TargetModel.label(forRaw: targetModel) }
  public var modeLabel: String { EnhanceMode.label(forRaw: mode) }
  public var updatedDate: Date? { PostgresDate.parse(updatedAt) }
}

public struct DraftRow: Codable, Sendable, Hashable {
  public var id: String
  public var title: String
  public var body: String
  public var target_model: String
  public var mode: String
  public var thinking_level: String?
  public var created_at: String
  public var updated_at: String

  public var card: DraftCard {
    DraftCard(
      id: id, title: title, preview: String(body.prefix(DraftCard.previewChars)),
      targetModel: target_model, mode: mode, thinkingLevel: thinking_level, createdAt: created_at,
      updatedAt: updated_at
    )
  }
}

/// Version metadata — bodies load lazily (web: VersionMeta).
public struct VersionMeta: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var mode: String
  public var model_used: String
  public var token_in: Int
  public var token_out: Int
  public var created_at: String
  public var parent_ver: String?

  public var modeLabel: String { EnhanceMode.label(forRaw: mode) }
  public var createdDate: Date? { PostgresDate.parse(created_at) }
}

public struct VersionBody: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var input_text: String
  public var output_text: String
  public var rationale: String?
}

public struct PromptHead: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var title: String
  public var target_model: String
  public var tags: [String]
  public var current_ver: String?
  public var collection_id: String?
  public var favorite: Bool?
  public var archived_at: String?
  public var deleted_at: String?

  public var target: TargetModel? { TargetModel.resolve(target_model) }
  public var modelLabel: String { TargetModel.label(forRaw: target_model) }
}

/// Activity feed row (web: ActivityFeed).
public struct ActivityEvent: Sendable, Hashable, Identifiable {
  public enum Kind: String, Codable, Sendable {
    case created
    case enhanced
    case saved
    case shared
    case restored
    case profileUpdated = "profile_updated"

    public var verb: String {
      switch self {
      case .created: "Created"
      case .enhanced: "Enhanced"
      case .saved: "Saved"
      case .shared: "Shared"
      case .restored: "Restored a version of"
      case .profileUpdated: "Updated profile"
      }
    }
  }

  public var id: String
  public var kind: Kind?
  public var rawType: String
  public var title: String?
  public var createdAt: String
  public var promptID: String?

  public init(
    id: String, rawType: String, title: String?, createdAt: String, promptID: String?
  ) {
    self.id = id
    self.rawType = rawType
    self.kind = Kind(rawValue: rawType)
    self.title = title
    self.createdAt = createdAt
    self.promptID = promptID
  }

  /// "Restored a version" when an older restored row carries no title —
  /// never a dangling "…of".
  public var verb: String {
    guard let kind else { return rawType }
    if kind == .restored, title == nil { return "Restored a version" }
    return kind.verb
  }

  public var showsTitle: Bool { kind != .profileUpdated && title != nil }
  public var createdDate: Date? { PostgresDate.parse(createdAt) }
}

public struct Collection: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var name: String
  public var created_at: String?
  public var updated_at: String?
}

/// A `media_assets` row as the Settings media manager lists it.
public struct MediaAssetRow: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var storage_path: String
  public var kind: String
  public var size_bytes: Int
  public var created_at: String
  public var original_name: String?
  public var mime_type: String?
  public var role: String?
  public var status: String
}
