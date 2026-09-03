import Foundation
import Observation
import VizionCore

/// The rendered result + the snapshot of what was actually SUBMITTED (web:
/// `stores/enhance-view.ts`). The result tree reads these, not the live
/// store values: flipping a mode or target after a run must not relabel the
/// save payload or the exports.
struct EnhanceView: Codable, Sendable, Hashable {
  struct Submitted: Codable, Sendable, Hashable {
    var input: String
    var mode: EnhanceMode
    var target: TargetModel
    var format: OutputFormat?
    var length: LengthSetting?
  }

  var submitted: Submitted
  var result: EnhanceResult
  /// True once a refinement pass replaced the result — the diff's input side
  /// is then the previous result, not the author's original.
  var refined: Bool?
  /// Polish's per-change review: hunk indices the user REVERTED.
  var rejected: [Int]?

  /// The model that ACTUALLY ran. Under Auto the submitted target is only the
  /// fallback the client sent; the server reports what it resolved to.
  var effectiveTarget: TargetModel { result.resolvedTarget ?? submitted.target }

  var rejectedSet: Set<Int> { Set(rejected ?? []) }

  /// What Copy/Use/Save/Share/export all consume — the output with the
  /// user's per-change decisions applied.
  var effectiveOutput: String {
    guard submitted.mode == .polish, let diff = result.diff, !rejectedSet.isEmpty else { return result.output }
    return WordDiff.applyDecisions(diff, rejected: rejectedSet)
  }
}

/// The composer's last finished enhancement, lifted OUT of screen state so
/// it survives navigation and relaunch. Server state is still the source of
/// truth for anything SAVED; this is the one artifact that exists nowhere
/// else until the user saves or copies it. Scoped to the account.
@MainActor
@Observable
final class EnhanceViewStore {
  static let storageKey = "vizion.enhance-view.v1"

  private(set) var view: EnhanceView?
  private(set) var userID: String?
  private let defaults: UserDefaults

  private struct Persisted: Codable {
    var userId: String?
    var view: EnhanceView?
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.storageKey), let p = try? JSONDecoder().decode(Persisted.self, from: data) {
      // Validated on every rehydrate: a result for a target the roster has
      // since renamed is dropped rather than re-keyed — it is a cache of one run.
      view = p.view
      userID = p.userId
    }
  }

  func set(_ view: EnhanceView?, userID: String?) {
    self.view = view
    self.userID = view == nil ? nil : userID
    persist()
  }

  func update(_ change: (inout EnhanceView) -> Void) {
    guard var current = view else { return }
    change(&current)
    view = current
    persist()
  }

  /// On a shared device another account's result is wiped before it renders.
  func adopt(userID: String) {
    if let owner = self.userID, owner != userID {
      view = nil
      self.userID = nil
      persist()
    }
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(Persisted(userId: userID, view: view)) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }
}
