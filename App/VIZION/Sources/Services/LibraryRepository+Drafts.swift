import Foundation
import Supabase
import VizionCore

/// Collections and drafts (web: `library/actions.ts` collections, `drafts/*`).
extension LibraryRepository {
  // MARK: Collections

  func setCollection(promptID: String, collectionID: String?) async throws {
    let uid = try await userID()
    if let collectionID {
      let owned: [IDRow] = try await client.from("collections")
        .select("id").eq("id", value: collectionID).eq("user_id", value: uid).limit(1).execute()
        .value
      if owned.isEmpty {
        throw Failure.message("That collection doesn't exist.")
      }
    }
    try await updatePrompt(promptID, ["collection_id": collectionID.map(AnyJSON.string) ?? .null])
  }

  private static func collectionName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1 ... 60).contains(trimmed.count)
    else { throw Failure.message("Give it a short name (1–60 characters).") }
    return trimmed
  }

  func createCollection(name: String) async throws -> String {
    let uid = try await userID()
    let trimmed = try Self.collectionName(name)
    do {
      let row: IDRow = try await client.from("collections")
        .insert(["user_id": AnyJSON.string(uid), "name": .string(trimmed)])
        .select("id").single().execute().value
      return row.id
    } catch {
      if "\(error)"
        .contains("23505") {
        throw Failure.message("You already have a collection with that name.")
      }
      throw error
    }
  }

  func renameCollection(id: String, name: String) async throws {
    let uid = try await userID()
    let trimmed = try Self.collectionName(name)
    try await client.from("collections")
      .update(["name": AnyJSON.string(trimmed), "updated_at": .string(PostgresDate.format(Date()))])
      .eq("id", value: id).eq("user_id", value: uid).execute()
  }

  /// Prompts inside are kept — the FK's ON DELETE SET NULL releases them.
  func deleteCollection(id: String) async throws {
    let uid = try await userID()
    try await client.from("collections").delete().eq("id", value: id).eq("user_id", value: uid)
      .execute()
  }

  // MARK: Drafts

  struct DraftInput: Sendable {
    static let maxBody = 100_000
    var body: String
    var target: TargetModel
    var mode: EnhanceMode
    var thinkingLevel: ThinkingLevel?

    func validate() -> String? {
      if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Nothing to save."
      }
      if body.utf16.count > Self.maxBody {
        return "That draft is too long to save."
      }
      return nil
    }
  }

  func draftsPage(filter: LibraryFilter, cursor: String? = nil) async throws -> Page<DraftCard> {
    var query = client.from("drafts")
      .select("id, title, body, target_model, mode, thinking_level, created_at, updated_at")
    if let q = filter.q {
      query = query.or(LibraryPaging.draftsSearchExpression(q))
    }
    if let model = filter.model {
      query = query.eq("target_model", value: model.rawValue)
    }
    if let mode = filter.mode {
      query = query.eq("mode", value: mode.rawValue)
    }
    if let cursor, let decoded = LibraryPaging.decodeCursor(cursor) {
      query = query.or(LibraryPaging.draftsCursorExpression(cursor: decoded))
    }
    let rows: [DraftRow] = try await query
      .order("updated_at", ascending: false)
      .order("id", ascending: false)
      .limit(LibraryPaging.pageSize + 1)
      .execute().value
    let page = Array(rows.prefix(LibraryPaging.pageSize))
    let next = rows.count > LibraryPaging.pageSize
      ? page.last.map { LibraryPaging.encodeCursor(value: $0.updated_at, id: $0.id) } : nil
    return Page(cards: page.map(\.card), nextCursor: next)
  }

  func saveDraft(_ input: DraftInput) async throws -> String {
    if let invalid = input.validate() {
      throw Failure.message(invalid)
    }
    let uid = try await userID()
    let row: IDRow = try await client.from("drafts")
      .insert([
        "user_id": AnyJSON.string(uid),
        "body": .string(input.body),
        "title": .string(LibraryUtil.deriveTitle(input.body)),
        "target_model": .string(input.target.rawValue),
        "mode": .string(input.mode.rawValue),
        "thinking_level": input.thinkingLevel.map { .string($0.rawValue) } ?? .null,
      ])
      .select("id").single().execute().value
    return row.id
  }

  struct DraftBody: Sendable {
    var body: String
    var updatedAt: String
  }

  private struct DraftBodyRow: Decodable {
    var body: String
    var updated_at: String
  }

  func draftBody(id: String) async throws -> DraftBody {
    let uid = try await userID()
    let row: DraftBodyRow = try await client.from("drafts")
      .select("body, updated_at").eq("id", value: id).eq("user_id", value: uid).single().execute()
      .value
    return DraftBody(body: row.body, updatedAt: row.updated_at)
  }

  /// Edit in place with optimistic concurrency: `expectedUpdatedAt` is part of
  /// the WHERE clause, so a stale editor cannot silently overwrite a newer body.
  func updateDraft(id: String, body: String, expectedUpdatedAt: String) async throws {
    let input = DraftInput(body: body, target: .opus5, mode: .clarify)
    if let invalid = input.validate() {
      throw Failure.message(invalid)
    }
    let uid = try await userID()
    let updated: [IDRow] = try await client.from("drafts")
      .update([
        "body": AnyJSON.string(body),
        "title": .string(LibraryUtil.deriveTitle(body)),
        "updated_at": .string(PostgresDate.format(Date())),
      ])
      .eq("id", value: id).eq("user_id", value: uid).eq("updated_at", value: expectedUpdatedAt)
      .select("id").execute().value
    if updated.isEmpty {
      let still: [IDRow] = try await client.from("drafts").select("id").eq("id", value: id).eq(
        "user_id",
        value: uid
      ).limit(1).execute().value
      throw Failure.message(
        still
          .isEmpty ? "That draft is no longer there." :
          "This draft changed somewhere else. Reopen it to get the latest version."
      )
    }
  }

  func deleteDraft(id: String) async throws {
    let uid = try await userID()
    try await client.from("drafts").delete().eq("id", value: id).eq("user_id", value: uid).execute()
  }
}
