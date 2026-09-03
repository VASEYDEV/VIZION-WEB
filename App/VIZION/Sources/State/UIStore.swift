import Foundation
import Observation
import VizionCore

/// Lightweight device-local UI state (web: `stores/ui.ts`). Persisted to
/// UserDefaults purely for convenience — none of this is authoritative; the
/// server wins. Writes are debounced (the draft persists per keystroke).
@MainActor
@Observable
final class UIStore {
  static let storageKey = "vizion.ui.v1"

  /// The account this state belongs to; a mismatch on hydrate drops the
  /// previous user's draft on a shared device.
  var userID: String? { didSet { scheduleSave() } }
  var theme: AppTheme = .system { didSet { scheduleSave() } }
  var activeMode: EnhanceMode = .default { didSet { scheduleSave() } }
  var targetModel: TargetModel = .default { didSet { scheduleSave() } }
  /// Chosen reasoning depth PER TARGET. No entry = "Auto" = provider default.
  var thinkingLevels: [TargetModel: ThinkingLevel] = [:] { didSet { scheduleSave() } }
  var editorDraft = "" { didSet { scheduleSave() } }
  var mediaNoticeAcknowledged = false { didSet { scheduleSave() } }
  var mediaStoreByDefault = true { didSet { scheduleSave() } }
  var reducedEffects = false { didSet { scheduleSave() } }
  /// Let the server pick the model per run; `targetModel` stays as the fallback.
  var autoTarget = false { didSet { scheduleSave() } }
  var autoPreference: AutoPreference = .default { didSet { scheduleSave() } }
  var dialTipSeen = false { didSet { scheduleSave() } }
  var reformatFormat: OutputFormat? { didSet { scheduleSave() } }
  var lengthByMode: [EnhanceMode: LengthSetting] = [:] { didSet { scheduleSave() } }

  private let defaults: UserDefaults
  private var saveTask: Task<Void, Never>?
  private var loading = true

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
    loading = false
  }

  // MARK: Derived

  var thinkingLevel: ThinkingLevel? {
    get {
      guard let level = thinkingLevels[targetModel], targetModel.thinkingLadder.contains(level) else { return nil }
      return level
    }
    set {
      if let newValue { thinkingLevels[targetModel] = newValue } else { thinkingLevels.removeValue(forKey: targetModel) }
    }
  }

  var lengthForActiveMode: LengthSetting? {
    get { activeMode.hasLengthControl ? lengthByMode[activeMode] : nil }
    set {
      if let newValue { lengthByMode[activeMode] = newValue } else { lengthByMode.removeValue(forKey: activeMode) }
    }
  }

  /// Once per load, Settings is authoritative for what the app opens on: a
  /// stored default starts with Auto off, a cleared one on Auto.
  func hydrate(profile: Profile?, userID: String) {
    if self.userID != nil, self.userID != userID {
      // Another account on this device — its draft is not this user's.
      editorDraft = ""
      thinkingLevels = [:]
    }
    self.userID = userID
    if let theme = profile?.theme { self.theme = theme }
    if let model = profile?.defaultTarget {
      targetModel = model
      autoTarget = false
    } else {
      autoTarget = true
    }
  }

  // MARK: Persistence

  private struct Persisted: Codable {
    var userId: String?
    var theme: String?
    var activeMode: String?
    var targetModel: String?
    var thinkingLevels: [String: String]?
    var editorDraft: String?
    var mediaNoticeAcknowledged: Bool?
    var mediaStoreByDefault: Bool?
    var reducedEffects: Bool?
    var autoTarget: Bool?
    var autoPreference: String?
    var dialTipSeen: Bool?
    var reformatFormat: String?
    var lengthByMode: [String: String]?
  }

  private func load() {
    guard let data = defaults.data(forKey: Self.storageKey),
      let p = try? JSONDecoder().decode(Persisted.self, from: data)
    else { return }
    userID = p.userId
    theme = AppTheme(rawValue: p.theme ?? "") ?? .system
    activeMode = EnhanceMode(rawValue: p.activeMode ?? "") ?? .default
    // A stale persisted ID would 400 on /api/enhance — map legacy values.
    targetModel = TargetModel.resolve(p.targetModel) ?? .default
    var levels: [TargetModel: ThinkingLevel] = [:]
    for (key, raw) in p.thinkingLevels ?? [:] {
      guard let target = TargetModel.resolve(key), let level = ThinkingLevel(rawValue: raw),
        target.thinkingLadder.contains(level)
      else { continue }
      levels[target] = level
    }
    thinkingLevels = levels
    editorDraft = p.editorDraft ?? ""
    mediaNoticeAcknowledged = p.mediaNoticeAcknowledged ?? false
    mediaStoreByDefault = p.mediaStoreByDefault ?? true
    reducedEffects = p.reducedEffects ?? false
    autoTarget = p.autoTarget ?? false
    autoPreference = AutoPreference(rawValue: p.autoPreference ?? "") ?? .default
    dialTipSeen = p.dialTipSeen ?? false
    reformatFormat = OutputFormat(rawValue: p.reformatFormat ?? "")
    var lengths: [EnhanceMode: LengthSetting] = [:]
    for (key, raw) in p.lengthByMode ?? [:] {
      if let mode = EnhanceMode(rawValue: key), mode.hasLengthControl, let length = LengthSetting(rawValue: raw) {
        lengths[mode] = length
      }
    }
    lengthByMode = lengths
  }

  private func snapshot() -> Persisted {
    Persisted(
      userId: userID, theme: theme.rawValue, activeMode: activeMode.rawValue, targetModel: targetModel.rawValue,
      thinkingLevels: Dictionary(uniqueKeysWithValues: thinkingLevels.map { ($0.key.rawValue, $0.value.rawValue) }),
      editorDraft: editorDraft, mediaNoticeAcknowledged: mediaNoticeAcknowledged,
      mediaStoreByDefault: mediaStoreByDefault, reducedEffects: reducedEffects, autoTarget: autoTarget,
      autoPreference: autoPreference.rawValue, dialTipSeen: dialTipSeen, reformatFormat: reformatFormat?.rawValue,
      lengthByMode: Dictionary(uniqueKeysWithValues: lengthByMode.map { ($0.key.rawValue, $0.value.rawValue) })
    )
  }

  private func scheduleSave() {
    guard !loading else { return }
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      self?.saveNow()
    }
  }

  func saveNow() {
    saveTask?.cancel()
    if let data = try? JSONEncoder().encode(snapshot()) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }
}
