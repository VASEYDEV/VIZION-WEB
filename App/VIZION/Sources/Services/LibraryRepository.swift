import Foundation
import Supabase
import VizionCore

/// Library, drafts, collections, and activity over PostgREST — the same
/// queries the web's server actions run (`library/queries.ts`, `actions.ts`,
/// `drafts/*`), from the user's own JWT so RLS scopes every row. Writes also
/// scope on `user_id` — belt and braces, as the web does.
final class LibraryRepository: Sendable {
  /// Internal, not private: `LibraryRepository+Drafts.swift` extends this type.
  let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  struct Page<Card: Sendable>: Sendable {
    var cards: [Card]
    var nextCursor: String?
  }

  enum Failure: Error, LocalizedError {
    case sessionExpired
    case duplicate(promptID: String, title: String)
    case message(String)

    var errorDescription: String? {
      switch self {
      case .sessionExpired: "Your session expired — sign in again."
      case let .duplicate(_, title): "That's already in your library as “\(title)”."
      case let .message(text): text
      }
    }
  }

  func userID() async throws -> String {
    guard let session = client.auth.currentSession else { throw Failure.sessionExpired }
    return session.user.id.uuidString.lowercased()
  }

  private static let pageSelect = [
    "id", "title", "target_model", "tags", "created_at", "updated_at", "favorite", "archived_at",
    "deleted_at", "preview", "current_mode", "collection_id", "prompt_versions!prompt_id(count)",
  ].joined(separator: ", ")

  // MARK: Prompts — read

  func page(filter: LibraryFilter, cursor: String? = nil) async throws -> Page<PromptCard> {
    var query = client.from("prompts").select(Self.pageSelect)
    if filter.view == .trash {
      query = query.not("deleted_at", operator: .is, value: "null")
    } else {
      query = query.is("deleted_at", value: nil)
    }
    switch filter.view {
    case .favorites:
      query = query.eq("favorite", value: true).is("archived_at", value: nil)
    case .archived:
      query = query.not("archived_at", operator: .is, value: "null")
    case .trash, .drafts:
      break
    case .all:
      query = query.is("archived_at", value: nil)
    }
    if let model = filter.model {
      query = query.eq("target_model", value: model.rawValue)
    }
    if let mode = filter.mode {
      query = query.eq("current_mode", value: mode.rawValue)
    }
    if let tag = filter.tag {
      query = query.contains("tags", value: [tag])
    }
    if let collection = filter.collection {
      query = query.eq("collection_id", value: collection)
    }
    if let q = filter
      .q {
      query = query.ilike("title", pattern: "%\(LibraryPaging.escapeLike(q))%")
    }
    if let cursor, let decoded = LibraryPaging.decodeCursor(cursor) {
      query = query.or(LibraryPaging.cursorExpression(sort: filter.sort, cursor: decoded))
    }
    let rows: [PromptPageRow] = try await query
      .order(filter.sort.column, ascending: filter.sort.ascending)
      .order("id", ascending: false)
      .limit(LibraryPaging.pageSize + 1)
      .execute()
      .value
    let page = Array(rows.prefix(LibraryPaging.pageSize))
    var next: String?
    if rows.count > LibraryPaging.pageSize, let last = page.last {
      let value: String = switch filter.sort {
      case .updated: last.updated_at
      case .created: last.created_at
      case .title: last.title
      }
      next = LibraryPaging.encodeCursor(value: value, id: last.id)
    }
    return Page(cards: page.map(\.card), nextCursor: next)
  }

  private struct FacetRow: Decodable {
    var target_model: String
    var tags: [String]?
    var collection_id: String?
  }

  func facets() async throws -> LibraryFacets {
    async let rowsTask: [FacetRow] = client.from("prompts")
      .select("target_model, tags, collection_id")
      .is("deleted_at", value: nil)
      .order("updated_at", ascending: false)
      .limit(1000)
      .execute().value
    async let collectionsTask: [Collection] = client.from("collections")
      .select("id, name")
      .order("name")
      .execute().value
    let (rows, collections) = try await (rowsTask, collectionsTask)
    return LibraryFacets.reduce(
      rows: rows.map { ($0.target_model, $0.tags ?? [], $0.collection_id) },
      collections: collections.map { ($0.id, $0.name) }
    )
  }

  func head(id: String) async throws -> PromptHead {
    try await client.from("prompts")
      .select(
        "id, title, target_model, tags, current_ver, collection_id, favorite, archived_at, deleted_at"
      )
      .eq("id", value: id)
      .single()
      .execute().value
  }

  func versions(promptID: String) async throws -> [VersionMeta] {
    try await client.from("prompt_versions")
      .select("id, mode, model_used, token_in, token_out, created_at, parent_ver")
      .eq("prompt_id", value: promptID)
      .order("created_at", ascending: true)
      .execute().value
  }

  func versionBody(promptID: String, versionID: String) async throws -> VersionBody {
    try await client.from("prompt_versions")
      .select("id, input_text, output_text, rationale")
      .eq("id", value: versionID)
      .eq("prompt_id", value: promptID)
      .single()
      .execute().value
  }

  private struct ActivityRow: Decodable {
    var id: String
    var type: String
    var meta: [String: AnyJSON]?
    var created_at: String
    var prompt_id: String?
  }

  func activity(limit: Int = 20) async throws -> [ActivityEvent] {
    let rows: [ActivityRow] = try await client.from("activity_events")
      .select("id, type, meta, created_at, prompt_id")
      .order("created_at", ascending: false)
      .limit(limit)
      .execute().value
    return rows.map { row in
      let title: String? = if case let .string(t)? = row.meta?["title"] {
        t
      } else {
        nil
      }
      return ActivityEvent(
        id: row.id,
        rawType: row.type,
        title: title,
        createdAt: row.created_at,
        promptID: row.prompt_id
      )
    }
  }

  // MARK: Prompts — write

  struct VersionInput: Sendable {
    var input: String
    var output: String
    var rationale: String?
    var mode: EnhanceMode
    var target: TargetModel
    var modelUsed: String
    var tokenIn: Int
    var tokenOut: Int
    /// Model-suggested semantic title (envelope `title`).
    var title: String?

    func validate() -> String? {
      if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Nothing to save."
      }
      return nil
    }

    var hash: String {
      LibraryUtil.contentHash(
        input: input,
        output: output,
        mode: mode.rawValue,
        target: target.rawValue
      )
    }
  }

  private struct SaveParams: Encodable {
    var p_title: String
    var p_target: String
    var p_tags: [String]
    var p_input: String
    var p_output: String
    var p_rationale: String?
    var p_mode: String
    var p_model_used: String
    var p_token_in: Int
    var p_token_out: Int
    var p_content_hash: String
  }

  private struct DuplicateRow: Decodable {
    struct Parent: Decodable {
      var title: String?
      var deleted_at: String?
    }

    var prompt_id: String
    var prompts: Parent?
  }

  /// Save an enhancement as a new Prompt + its first immutable version. Exact
  /// duplicates (same input+output+mode+target) surface as `.duplicate`.
  func savePrompt(
    _ v: VersionInput,
    title: String? = nil,
    tags: [String] = []
  ) async throws -> String {
    if let invalid = v.validate() {
      throw Failure.message(invalid)
    }
    _ = try await userID()
    let hash = v.hash
    let dups: [DuplicateRow] = try await client.from("prompt_versions")
      .select("prompt_id, prompts!prompt_id!inner(title, deleted_at)")
      .eq("content_hash", value: hash)
      .is("prompts.deleted_at", value: nil)
      .limit(1)
      .execute().value
    if let dup = dups.first {
      throw Failure.duplicate(promptID: dup.prompt_id, title: dup.prompts?.title ?? "Saved prompt")
    }
    let promptTitle = [title, v.title]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? LibraryUtil.deriveTitle(v.input)
    let params = SaveParams(
      p_title: promptTitle, p_target: v.target.rawValue, p_tags: tags, p_input: v.input,
      p_output: v.output, p_rationale: v.rationale, p_mode: v.mode.rawValue,
      p_model_used: v.modelUsed,
      p_token_in: v.tokenIn, p_token_out: v.tokenOut, p_content_hash: hash
    )
    return try await client.rpc("library_save_prompt", params: params).execute().value
  }

  private struct AddVersionParams: Encodable {
    var p_prompt_id: String
    var p_input: String
    var p_output: String
    var p_rationale: String?
    var p_mode: String
    var p_model_used: String
    var p_token_in: Int
    var p_token_out: Int
    var p_content_hash: String
  }

  private struct CurrentVersion: Decodable {
    var current_ver: String?
  }

  private struct HashRow: Decodable {
    var content_hash: String?
  }

  /// Append a new immutable version (parent = current) and make it current.
  func addVersion(promptID: String, _ v: VersionInput) async throws -> String {
    if let invalid = v.validate() {
      throw Failure.message(invalid)
    }
    let uid = try await userID()
    let hash = v.hash
    let current: CurrentVersion? = try await client.from("prompts")
      .select("current_ver")
      .eq("id", value: promptID)
      .eq("user_id", value: uid)
      .is("deleted_at", value: nil)
      .single()
      .execute().value
    if let currentID = current?.current_ver {
      let cur: HashRow? = try await client.from("prompt_versions")
        .select("content_hash")
        .eq("id", value: currentID)
        .single()
        .execute().value
      if cur?
        .content_hash == hash {
        throw Failure.message("That's identical to the current version.")
      }
    }
    let params = AddVersionParams(
      p_prompt_id: promptID, p_input: v.input, p_output: v.output, p_rationale: v.rationale,
      p_mode: v.mode.rawValue, p_model_used: v.modelUsed, p_token_in: v.tokenIn,
      p_token_out: v.tokenOut, p_content_hash: hash
    )
    return try await client.rpc("library_add_version", params: params).execute().value
  }

  private struct RestoreSource: Decodable {
    var output_text: String
    var mode: String
  }

  private struct TitleRow: Decodable {
    var title: String?
  }

  /// Restore a version: point current_ver at it (versions stay immutable).
  func restoreVersion(promptID: String, versionID: String) async throws {
    let uid = try await userID()
    let restored: RestoreSource = try await client.from("prompt_versions")
      .select("output_text, mode")
      .eq("id", value: versionID)
      .eq("prompt_id", value: promptID)
      .single()
      .execute().value
    let updated: TitleRow = try await client.from("prompts")
      .update([
        "current_ver": AnyJSON.string(versionID),
        "preview": .string(String(restored.output_text.prefix(200))),
        "current_mode": .string(restored.mode),
      ])
      .eq("id", value: promptID)
      .eq("user_id", value: uid)
      .select("title")
      .single()
      .execute().value
    try await client.from("activity_events").insert([
      "user_id": AnyJSON.string(uid),
      "prompt_id": .string(promptID),
      "type": .string("restored"),
      "meta": .object(["version_id": .string(versionID), "title": .string(updated.title ?? "")]),
    ]).execute()
  }

  func updatePrompt(_ id: String, _ patch: [String: AnyJSON]) async throws {
    let uid = try await userID()
    try await client.from("prompts").update(patch).eq("id", value: id).eq("user_id", value: uid)
      .execute()
  }

  func updateTags(promptID: String, tags: [String]) async throws {
    try await updatePrompt(promptID, ["tags": .array(tags.map(AnyJSON.string))])
  }

  func updateTitle(promptID: String, title: String) async throws {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1 ... 120).contains(trimmed.count)
    else { throw Failure.message("Give it a short name (1–120 characters).") }
    try await updatePrompt(promptID, ["title": .string(trimmed)])
  }

  func setFavorite(promptID: String, _ favorite: Bool) async throws {
    try await updatePrompt(promptID, ["favorite": .bool(favorite)])
  }

  func setArchived(promptID: String, _ archived: Bool) async throws {
    try await updatePrompt(
      promptID,
      ["archived_at": archived ? .string(PostgresDate.format(Date())) : .null]
    )
  }

  /// Soft delete — recoverable from Recently deleted (and the toast's Undo).
  func softDelete(promptID: String) async throws {
    try await updatePrompt(promptID, ["deleted_at": .string(PostgresDate.format(Date()))])
  }

  func undoDelete(promptID: String) async throws {
    try await updatePrompt(promptID, ["deleted_at": .null])
  }

  struct IDRow: Decodable {
    var id: String
  }

  /// Permanent delete — archived or trashed prompts only, as the web enforces.
  func deleteForever(promptID: String) async throws {
    let uid = try await userID()
    let deleted: [IDRow] = try await client.from("prompts")
      .delete()
      .eq("id", value: promptID)
      .eq("user_id", value: uid)
      .or("archived_at.not.is.null,deleted_at.not.is.null")
      .select("id")
      .execute().value
    if deleted
      .isEmpty {
      throw Failure.message("Only archived or deleted prompts can be permanently deleted.")
    }
  }

  func logShare(promptID: String) async throws {
    let uid = try await userID()
    try await client.from("activity_events").insert([
      "user_id": AnyJSON.string(uid), "prompt_id": .string(promptID), "type": .string("shared"),
      "meta": .object([:]),
    ]).execute()
  }
}
