import Foundation
import Observation
import VizionCore

/// Library state (web: `LibraryBrowser` + `DraftsList`): server-side filter
/// and keyset pagination; this only accumulates "Load more" pages and funnels
/// every mutation through a reload so a refreshed page 1 can't duplicate a
/// stale extra page.
@MainActor
@Observable
final class LibraryViewModel {
  let env: AppEnvironment

  var filter = LibraryFilter
    .default {
    didSet {
      if filter != oldValue {
        Task { await reload() }
      }
    }
  }

  var searchDraft = ""
  private(set) var cards: [PromptCard] = []
  private(set) var drafts: [DraftCard] = []
  private(set) var nextCursor: String?
  private(set) var facets = LibraryFacets.empty
  private(set) var activity: [ActivityEvent] = []
  private(set) var loading = false
  private(set) var loadingMore = false
  private(set) var error: String?
  private(set) var draftsUnavailable = false
  /// Bumped per reload; a response from an older generation is discarded so
  /// rapid filter changes can't show results for a filter no longer selected.
  private var reloadGeneration = 0

  init(env: AppEnvironment) {
    self.env = env
  }

  private var library: LibraryRepository? {
    env.library
  }

  func submitSearch() {
    let q = searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    filter = LibraryFilter(
      q: q.isEmpty ? nil : q, model: filter.model, mode: filter.mode, tag: filter.tag,
      collection: filter.collection, view: filter.view, sort: filter.sort
    )
  }

  func reload() async {
    guard let library else { return }
    reloadGeneration += 1
    let generation = reloadGeneration
    let filter = filter
    loading = true
    error = nil
    defer {
      if generation == reloadGeneration {
        loading = false
      }
    }
    do {
      if filter.isDraftsView {
        let page = try await library.draftsPage(filter: filter)
        guard generation == reloadGeneration else { return }
        drafts = page.cards
        nextCursor = page.nextCursor
        draftsUnavailable = false
      } else {
        async let pageTask = library.page(filter: filter)
        async let facetsTask = library.facets()
        async let activityTask = library.activity()
        let (page, facets, activity) = try await (pageTask, facetsTask, activityTask)
        guard generation == reloadGeneration else { return }
        cards = page.cards
        nextCursor = page.nextCursor
        self.facets = facets
        self.activity = activity
      }
    } catch {
      guard generation == reloadGeneration else { return }
      let text = "\(error)"
      if filter.isDraftsView, text.contains("PGRST205") {
        draftsUnavailable = true
        drafts = []
      } else {
        self.error = """
        Couldn't load your library — your prompts are safe on the server. \
        Check your connection and retry.
        """
      }
    }
  }

  func loadMore() async {
    guard let library, let cursor = nextCursor, !loadingMore else { return }
    loadingMore = true
    defer { loadingMore = false }
    do {
      if filter.isDraftsView {
        let page = try await library.draftsPage(filter: filter, cursor: cursor)
        let seen = Set(drafts.map(\.id))
        drafts += page.cards.filter { !seen.contains($0.id) }
        nextCursor = page.nextCursor
      } else {
        let page = try await library.page(filter: filter, cursor: cursor)
        let seen = Set(cards.map(\.id))
        cards += page.cards.filter { !seen.contains($0.id) }
        nextCursor = page.nextCursor
      }
    } catch {
      env.toasts.error("Couldn't load more.")
    }
  }

  // MARK: Mutations

  private func mutate(_ work: () async throws -> Void) async {
    do {
      try await work()
      await reload()
    } catch {
      env.toasts.error(error.localizedDescription)
    }
  }

  func toggleFavorite(_ card: PromptCard) async {
    await mutate { try await library?.setFavorite(promptID: card.id, !card.favorite) }
  }

  func setArchived(_ card: PromptCard, _ archived: Bool) async {
    await mutate { try await library?.setArchived(promptID: card.id, archived) }
    env.toasts.show(archived ? "Archived" : "Unarchived")
  }

  func softDelete(_ card: PromptCard) async {
    await mutate { try await library?.softDelete(promptID: card.id) }
    env.toasts.show("Moved to Recently deleted", actionLabel: "Undo") { [weak self] in
      Task { await self?.mutate { try await self?.library?.undoDelete(promptID: card.id) } }
    }
  }

  func restore(_ card: PromptCard) async {
    await mutate { try await library?.undoDelete(promptID: card.id) }
  }

  func deleteForever(_ card: PromptCard) async {
    await mutate { try await library?.deleteForever(promptID: card.id) }
  }

  func rename(_ card: PromptCard, to title: String) async {
    await mutate { try await library?.updateTitle(promptID: card.id, title: title) }
  }

  func move(_ card: PromptCard, to collectionID: String?) async {
    await mutate { try await library?.setCollection(promptID: card.id, collectionID: collectionID) }
  }

  func createCollection(_ name: String) async -> String? {
    do {
      let id = try await library?.createCollection(name: name)
      await reload()
      return id
    } catch {
      env.toasts.error(error.localizedDescription)
      return nil
    }
  }

  func renameCollection(_ id: String, to name: String) async {
    await mutate { try await library?.renameCollection(id: id, name: name) }
  }

  func deleteCollection(_ id: String) async {
    await mutate { try await library?.deleteCollection(id: id) }
  }

  // MARK: Drafts

  /// Resuming a draft is a MOVE: it lands in the composer and the row is deleted.
  func resume(_ draft: DraftCard) async -> Bool {
    guard let library else { return false }
    do {
      let body = try await library.draftBody(id: draft.id)
      let ui = env.ui
      ui.editorDraft = body.body
      if let mode = EnhanceMode(rawValue: draft.mode) {
        ui.activeMode = mode
      }
      if let target = TargetModel.resolve(draft.targetModel) {
        ui.targetModel = target
        ui.autoTarget = false
        if let level = draft.thinkingLevel.flatMap(ThinkingLevel.init(rawValue:)),
           target.thinkingLadder.contains(level) {
          ui.thinkingLevels[target] = level
        } else {
          ui.thinkingLevels.removeValue(forKey: target)
        }
      }
      try await library.deleteDraft(id: draft.id)
      await reload()
      return true
    } catch {
      env.toasts.error(error.localizedDescription)
      return false
    }
  }

  func deleteDraft(_ draft: DraftCard) async {
    await mutate { try await library?.deleteDraft(id: draft.id) }
  }

  func draftBody(_ draft: DraftCard) async -> LibraryRepository.DraftBody? {
    try? await library?.draftBody(id: draft.id)
  }

  func updateDraft(_ draft: DraftCard, body: String, expectedUpdatedAt: String) async -> Bool {
    do {
      try await library?.updateDraft(id: draft.id, body: body, expectedUpdatedAt: expectedUpdatedAt)
      await reload()
      return true
    } catch {
      env.toasts.error(error.localizedDescription)
      return false
    }
  }

  func saveComposerDraft() async -> Bool {
    let ui = env.ui
    do {
      _ = try await library?.saveDraft(
        LibraryRepository.DraftInput(
          body: ui.editorDraft,
          target: ui.targetModel,
          mode: ui.activeMode,
          thinkingLevel: ui.thinkingLevel
        )
      )
      await reload()
      return true
    } catch {
      env.toasts.error(error.localizedDescription)
      return false
    }
  }
}
