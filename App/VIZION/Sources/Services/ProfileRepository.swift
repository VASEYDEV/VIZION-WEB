import Foundation
import Supabase
import VizionCore

/// Profile, avatar, app settings (owner console), stored media, and the data
/// export — over PostgREST + Storage with the user's own JWT.
final class ProfileRepository: Sendable {
  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  enum Failure: Error, LocalizedError {
    case sessionExpired
    case message(String)

    var errorDescription: String? {
      switch self {
      case .sessionExpired: "Your session expired — sign in again."
      case let .message(text): text
      }
    }
  }

  private func userID() async throws -> String {
    guard let session = client.auth.currentSession else { throw Failure.sessionExpired }
    return session.user.id.uuidString.lowercased()
  }

  func profile() async throws -> Profile? {
    let uid = try await userID()
    let rows: [Profile] = try await client.from("profiles").select("*").eq("user_id", value: uid).limit(1).execute().value
    return rows.first
  }

  func appSettings() async throws -> AppSettings {
    let rows: [AppSettings] = try await client.from("app_settings")
      .select("owner_user_id, open_access, dev_accent_strength").eq("id", value: 1).limit(1).execute().value
    return rows.first ?? .defaults
  }

  struct ProfilePatch: Sendable {
    var fullName: String??
    var displayName: String??
    /// `.some(nil)` clears the stored default — the account then starts on Auto.
    var defaultModel: TargetModel??
    var theme: AppTheme?
    var avatarURL: String??
  }

  func update(_ patch: ProfilePatch) async throws {
    let uid = try await userID()
    var update: [String: AnyJSON] = [:]
    if let fullName = patch.fullName {
      let trimmed = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      update["full_name"] = trimmed.isEmpty ? .null : .string(trimmed)
    }
    if let displayName = patch.displayName {
      let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trimmed.isEmpty, !LibraryUtil.isValidDisplayName(trimmed) { throw Failure.message(LibraryUtil.displayNameRule) }
      update["display_name"] = trimmed.isEmpty ? .null : .string(trimmed)
    }
    if let defaultModel = patch.defaultModel { update["default_model"] = defaultModel.map { .string($0.rawValue) } ?? .null }
    if let theme = patch.theme { update["theme"] = .string(theme.rawValue) }
    if let avatarURL = patch.avatarURL { update["avatar_url"] = avatarURL.map(AnyJSON.string) ?? .null }
    guard !update.isEmpty else { return }
    do {
      try await client.from("profiles").update(update).eq("user_id", value: uid).execute()
    } catch {
      if "\(error)".contains("23505") { throw Failure.message("That display name is taken.") }
      throw error
    }
    if patch.fullName != nil || patch.displayName != nil || patch.avatarURL != nil {
      try? await client.from("activity_events").insert([
        "user_id": AnyJSON.string(uid), "type": .string("profile_updated"), "meta": .object([:]),
      ]).execute()
    }
  }

  /// Upload a PNG avatar to the fixed path and return the cache-busted public URL.
  func uploadAvatar(png: Data) async throws -> String {
    let uid = try await userID()
    let path = "\(uid)/avatar.png"
    try await client.storage.from("avatars").upload(path, data: png, options: FileOptions(contentType: "image/png", upsert: true))
    let url = try client.storage.from("avatars").getPublicURL(path: path)
    let busted = "\(url.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"
    try await update(ProfilePatch(avatarURL: .some(busted)))
    return busted
  }

  func setPasswordSet() async throws {
    let uid = try await userID()
    try await client.from("profiles").update(["password_set": AnyJSON.bool(true)]).eq("user_id", value: uid).execute()
  }

  // MARK: Owner console

  private struct OwnerParams: Encodable {
    var p_open_access: Bool?
    var p_dev_accent_strength: Int?
  }

  func updateAppSettings(openAccess: Bool? = nil, devAccentStrength: Int? = nil) async throws {
    try await client.rpc("update_app_settings", params: OwnerParams(p_open_access: openAccess, p_dev_accent_strength: devAccentStrength)).execute()
  }

  func claimOwnership() async throws -> Bool {
    try await client.rpc("claim_app_ownership").execute().value
  }

  // MARK: Stored media

  func mediaAssets() async throws -> [MediaAssetRow] {
    try await client.from("media_assets")
      .select("id, storage_path, kind, size_bytes, created_at, original_name, mime_type, role, status")
      .order("created_at", ascending: false)
      .execute().value
  }

  func deleteMediaAsset(_ asset: MediaAssetRow) async throws {
    let uid = try await userID()
    _ = try? await client.storage.from("media").remove(paths: [asset.storage_path])
    try await client.from("media_assets").delete().eq("id", value: asset.id).eq("user_id", value: uid).execute()
  }

  func signedMediaURL(path: String) async throws -> URL {
    try await client.storage.from("media").createSignedURL(path: path, expiresIn: 600)
  }

  // MARK: Media reserve → upload → commit (the web's `pipeline.ts`)

  private struct ReserveParams: Encodable {
    var p_kind: String
    var p_size_bytes: Int
    var p_original_name: String
    var p_mime_type: String
    var p_ext: String
    var p_role: String
  }

  struct Reserved: Decodable, Sendable {
    var id: String
    var storage_path: String
  }

  /// The DB row is created FIRST (quota enforced atomically), the object
  /// second; an upload failure deletes the pending row so nothing invisible
  /// keeps charging quota.
  func storeAttachment(data: Data, name: String, mime: String, kind: MediaKind, role: AttachmentRole) async throws -> Reserved {
    let params = ReserveParams(
      p_kind: kind.rawValue, p_size_bytes: data.count, p_original_name: name, p_mime_type: mime,
      p_ext: MediaKind.fileExtension(forMIME: mime), p_role: role.rawValue
    )
    let reserved: [Reserved]
    do {
      reserved = try await client.rpc("media_reserve", params: params).execute().value
    } catch {
      let text = "\(error)"
      if text.contains("quota_exceeded") { throw Failure.message(MediaBudget.quotaMessage) }
      if text.contains("invalid_size") { throw Failure.message("That file is too large to store (50 MB limit).") }
      throw error
    }
    guard let row = reserved.first else { throw Failure.message("Couldn't reserve storage.") }
    do {
      try await client.storage.from("media").upload(row.storage_path, data: data, options: FileOptions(contentType: mime))
      _ = try await client.rpc("media_commit", params: ["p_id": row.id]).execute()
      return row
    } catch {
      _ = try? await client.storage.from("media").remove(paths: [row.storage_path])
      let uid = (try? await userID()) ?? ""
      try? await client.from("media_assets").delete().eq("id", value: row.id).eq("user_id", value: uid).execute()
      throw error
    }
  }

  // MARK: Export

  private struct AnyRows: Decodable {}

  /// Profile, prompts + versions, and media METADATA as pretty JSON.
  func exportJSON() async throws -> Data {
    let uid = try await userID()
    async let profile: [[String: AnyJSON]] = client.from("profiles").select("*").eq("user_id", value: uid).execute().value
    async let prompts: [[String: AnyJSON]] = client.from("prompts").select("*").order("created_at", ascending: true).execute().value
    async let versions: [[String: AnyJSON]] = client.from("prompt_versions").select("*").order("created_at", ascending: true).execute().value
    async let media: [[String: AnyJSON]] = client.from("media_assets")
      .select("id, storage_path, kind, size_bytes, created_at, original_name, mime_type, role, status")
      .order("created_at", ascending: true).execute().value
    let payload: [String: AnyJSON] = [
      "exportedAt": .string(PostgresDate.format(Date())),
      "profile": try await profile.first.map(AnyJSON.object) ?? .null,
      "prompts": .array(try await prompts.map(AnyJSON.object)),
      "prompt_versions": .array(try await versions.map(AnyJSON.object)),
      "media_assets": .array(try await media.map(AnyJSON.object)),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(payload)
  }
}
