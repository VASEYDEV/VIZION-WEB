import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VizionCore

/// The composer's run/result/attachment logic (web: `EnhanceComposer` +
/// `use-enhance.ts` + `AttachmentTray`). Screen state that must survive
/// navigation lives in the stores; this holds the transient per-run state.
@MainActor
@Observable
final class EnhanceViewModel {
  let env: AppEnvironment

  private(set) var stream: EnhanceStreamState = .idle
  private(set) var isRunning = false
  var error: EnhanceFailure?
  private var runTask: Task<Void, Never>?
  /// Bumped by every start/cancel; a task whose generation is stale is a
  /// cancelled predecessor and must not mutate the replacement run's state.
  private var runGeneration = 0
  /// A refinement is a run over the CURRENT result; the chips show a spinner.
  private(set) var refinePending = false

  /// The `?draft=` offer when the editor already held work — no timer, stays
  /// until answered; replacing is undoable.
  var draftOffer: String?

  var attachments: [Attachment] = []
  /// The tray holds at most as many items as the prompt can carry as
  /// reference blocks; anything past that would be uploaded and analyzed
  /// for nothing.
  static let maxAttachments = MediaContext.maxItems
  var pendingPick: [PhotosPickerItem] = []
  var showPrivacyNotice = false
  private var queueTask: Task<Void, Never>?

  init(env: AppEnvironment) {
    self.env = env
  }

  var ui: UIStore {
    env.ui
  }

  var view: EnhanceView? {
    env.results.view
  }

  // MARK: Draft intake

  func consumePendingDraft() {
    guard let incoming = env.pendingDraft else { return }
    env.pendingDraft = nil
    switch DraftParam.resolve(incoming, currentDraft: ui.editorDraft) {
    case .none: break
    case let .apply(text): ui.editorDraft = text
    case let .conflict(text): draftOffer = text
    }
  }

  func acceptDraftOffer() {
    guard let text = draftOffer else { return }
    let prior = ui.editorDraft
    ui.editorDraft = text
    draftOffer = nil
    env.toasts.show("Draft replaced", actionLabel: "Undo") { [ui] in ui.editorDraft = prior }
  }

  func discardDraftOffer() {
    draftOffer = nil
  }

  func paste() {
    guard let text = UIPasteboard.general.string, !text.isEmpty else {
      env.toasts.error("Nothing to paste.")
      return
    }
    ui.editorDraft = text
  }

  func apply(template: PromptTemplate) {
    ui.editorDraft = template.text
    ui.activeMode = template.mode
  }

  /// Clear the draft + result, undoably. Clearing mid-run cancels the run.
  /// The tray is untouched (web `performClear`): a kept asset leaves only
  /// through Remove or Settings, so Clear can never orphan stored media.
  func clear() {
    let priorDraft = ui.editorDraft
    let priorView = view
    cancel()
    ui.editorDraft = ""
    env.results.set(nil, userID: env.session?.userID)
    error = nil
    if !priorDraft.isEmpty || priorView != nil {
      env.toasts.show("Cleared", actionLabel: "Undo") { [weak self] in
        guard let self else { return }
        ui.editorDraft = priorDraft
        env.results.set(priorView, userID: env.session?.userID)
      }
    }
  }

  // MARK: Run

  var tokenEstimate: Int {
    EnhanceStreamState.estimateTokens(chars: ui.editorDraft.utf16.count)
  }

  /// True while any attachment is still reserving/uploading/analyzing — a run
  /// started now would silently drop the visual context the user attached.
  var attachmentsPending: Bool {
    attachments.contains { attachment in
      switch attachment.status {
      case .ready, .error: false
      case .queued, .reserving, .uploading, .analyzing: true
      }
    }
  }

  var contextBlocks: [String] {
    MediaContext.build(attachments.map {
      MediaContextItem(
        role: $0.role,
        isReady: $0.status == .ready,
        name: $0.name,
        description: $0.description,
        attrs: $0.attrs
      )
    })
  }

  func run() {
    let request = EnhanceRequest(
      input: ui.editorDraft, mode: ui.activeMode, target: ui.targetModel, auto: ui.autoTarget,
      autoPreference: ui.autoPreference, format: ui.reformatFormat, length: ui.lengthForActiveMode,
      thinkingLevel: ui.thinkingLevel, mediaContext: contextBlocks
    )
    if let invalid = request.validate() {
      error = EnhanceFailure(message: invalid, status: 400)
      return
    }
    let submitted = EnhanceView.Submitted(
      input: request.input, mode: request.mode, target: request.target, format: request.format,
      length: request.length
    )
    start(request, submitted: submitted, refined: false)
  }

  /// Refinement pass — seeded from the CURRENT output (with any per-change
  /// decisions applied). Sticks to the model that produced this output.
  func refine(_ kind: RefineKind) {
    guard let view else { return }
    let baseInput: String? = kind == .tone ? view.submitted.input : nil
    let request = EnhanceRequest(
      input: view.effectiveOutput, mode: view.submitted.mode, target: view.effectiveTarget,
      format: view.submitted.format, length: view.submitted.length,
      thinkingLevel: ui.thinkingLevels[view.effectiveTarget]
        .flatMap { view.effectiveTarget.thinkingLadder.contains($0) ? $0 : nil },
      refine: EnhanceRefine(kind: kind, baseInput: baseInput)
    )
    refinePending = true
    start(request, submitted: view.submitted, refined: true)
  }

  /// Clarify's answered re-run: a redo of the ORIGINAL request with the
  /// answers attached — the diff's input side stays the author's own text.
  func answer(questions: [String], answers: [String]) {
    guard let view else { return }
    let request = EnhanceRequest(
      input: view.submitted.input, mode: view.submitted.mode, target: view.effectiveTarget,
      format: view.submitted.format, length: view.submitted.length,
      refine: EnhanceRefine(
        kind: .answers,
        baseInput: EnhanceRefine.answersBlock(questions: questions, answers: answers)
      )
    )
    start(request, submitted: view.submitted, refined: false)
  }

  private func start(_ request: EnhanceRequest, submitted: EnhanceView.Submitted, refined: Bool) {
    guard let api = env.api else { return }
    runTask?.cancel()
    runGeneration += 1
    let generation = runGeneration
    error = nil
    stream = .started()
    isRunning = true
    let userID = env.session?.userID
    runTask = Task { [weak self] in
      // Deltas are batched so the editor doesn't re-render per token.
      var pendingText = ""
      var lastFlush = ContinuousClock.now
      do {
        var done: EnhanceResult?
        for try await event in api.enhance(request) {
          guard let self else { return }
          guard generation == runGeneration else { return }
          switch event {
          case let .delta(text):
            pendingText += text
            if ContinuousClock.now - lastFlush > .milliseconds(40) {
              flush(&pendingText)
              lastFlush = .now
            }
          case let .error(status, message, notConfigured, capReached):
            throw EnhanceFailure(
              message: message,
              status: status,
              notConfigured: notConfigured,
              capReached: capReached
            )
          case let .done(result):
            done = result
            flush(&pendingText, applying: event)
          default:
            flush(&pendingText, applying: event)
          }
        }
        guard let self else { return }
        guard generation == runGeneration else { return }
        flush(&pendingText)
        guard let done else {
          throw EnhanceFailure(message: "The stream ended unexpectedly.", status: 502)
        }
        env.results.set(
          EnhanceView(
            submitted: submitted,
            result: done,
            refined: refined ? true : nil,
            rejected: nil
          ),
          userID: userID
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch let failure as EnhanceFailure {
        self?.finish(generation: generation, failure: failure)
        return
      } catch {
        let failure = error is CancellationError
          ? nil : EnhanceFailure(message: error.localizedDescription, status: 502)
        self?.finish(generation: generation, failure: failure)
        return
      }
      self?.finish(generation: generation, failure: nil)
    }
  }

  /// The run's epilogue. Ignored for a stale generation: a cancelled
  /// predecessor must not touch the replacement run's state.
  private func finish(generation: Int, failure: EnhanceFailure?) {
    guard generation == runGeneration else { return }
    if let failure, !failure.isCancelled {
      error = failure
    }
    isRunning = false
    refinePending = false
    var state = stream
    state.active = false
    stream = state
  }

  /// Applies the batched delta text — and, optionally, the event that ended
  /// the batch — to the stream state in one mutation, so observers see a
  /// single change per flush.
  private func flush(_ pending: inout String, applying event: EnhanceStreamEvent? = nil) {
    var state = stream
    if !pending.isEmpty {
      state.apply(.delta(text: pending))
      pending = ""
    }
    if let event {
      state.apply(event)
    }
    stream = state
  }

  func cancel() {
    runGeneration += 1
    runTask?.cancel()
    runTask = nil
    isRunning = false
    refinePending = false
    stream = .idle
  }

  // MARK: Result actions

  func copyOutput() {
    guard let view else { return }
    UIPasteboard.general.string = view.effectiveOutput
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    env.toasts.show("Copied")
  }

  /// "Use as draft" — replace the editor draft with the result, undoably.
  func useAsDraft() {
    guard let view else { return }
    let prior = ui.editorDraft
    ui.editorDraft = view.effectiveOutput
    env.toasts
      .show("Result moved into the editor", actionLabel: "Undo") { [ui] in ui.editorDraft = prior }
  }

  func setRejected(_ rejected: Set<Int>) {
    env.results.update { $0.rejected = rejected.isEmpty ? nil : rejected.sorted() }
  }

  func versionInput(title: String? = nil) -> LibraryRepository.VersionInput? {
    guard let view else { return nil }
    return LibraryRepository.VersionInput(
      input: view.submitted.input, output: view.effectiveOutput, rationale: view.result.rationale,
      mode: view.submitted.mode, target: view.effectiveTarget, modelUsed: view.result.modelUsed,
      tokenIn: view.result.tokenIn, tokenOut: view.result.tokenOut,
      title: title ?? view.result.title
    )
  }

  func exportData() -> ExportData? {
    guard let view else { return nil }
    return ExportData(
      input: view.submitted.input, output: view.effectiveOutput, rationale: view.result.rationale,
      mode: view.submitted.mode, target: view.effectiveTarget, modelUsed: view.result.modelUsed
    )
  }
}

// MARK: - Attachments

extension EnhanceViewModel {
  struct Attachment: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
      case queued
      case reserving
      case uploading
      case analyzing
      case ready
      case error(String)
    }

    let id = UUID()
    var name: String
    var kind: MediaKind
    var mime: String
    var bytes: Int
    var thumbnail: Data?
    var status: Status = .queued
    var role: AttachmentRole = .default
    var ephemeral: Bool
    var assetID: String?
    var storagePath: String?
    var attrs: MediaAttributes?
    var description: String?
    var extractedText: String?
    var usage: MediaAnalysisUsage?
    var inserted = false
    var analysisTarget: TargetModel?
    var analyzedIntent: MediaAnalysisIntent?
    var genTarget: GenTarget
    /// Downscaled JPEG for the vision call. Kept until removal so a later
    /// role change can re-analyze (the web keeps the File in `filesRef`).
    var analysisJPEG: Data?
    var original: Data?

    var stepLabel: String {
      switch status {
      case .queued: "Waiting…"
      case .reserving: "Reserving storage…"
      case .uploading: "Uploading…"
      case .analyzing: "Analyzing with \(analysisTarget?.label ?? "the model")…"
      case .ready: "Ready"
      case let .error(message): message
      }
    }
  }

  /// Photos picker results → queue (the privacy notice gates the FIRST pick
  /// on this device).
  func handlePicked(_ items: [PhotosPickerItem]) async {
    guard !items.isEmpty else { return }
    if !ui.mediaNoticeAcknowledged {
      pendingPick = items
      showPrivacyNotice = true
      return
    }
    await enqueue(items)
  }

  func acknowledgePrivacyNotice(keepByDefault: Bool) async {
    ui.mediaNoticeAcknowledged = true
    ui.mediaStoreByDefault = keepByDefault
    showPrivacyNotice = false
    let items = pendingPick
    pendingPick = []
    await enqueue(items)
  }

  var attachmentsFull: Bool {
    attachments.count >= Self.maxAttachments
  }

  private func enqueue(_ items: [PhotosPickerItem]) async {
    let room = max(0, Self.maxAttachments - attachments.count)
    if items.count > room {
      env.toasts.error("Up to \(Self.maxAttachments) attachments — the rest were skipped.")
    }
    for item in items.prefix(room) {
      guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
      let type = item.supportedContentTypes.first
      let mime = type?.preferredMIMEType ?? "image/jpeg"
      let isImage = type?.conforms(to: .image) ?? true
      guard isImage else {
        env.toasts.error("Only images are supported on iOS for now.")
        continue
      }
      let prepared = ImageProcessing.prepare(data, mime: mime)
      let stem = item.itemIdentifier.map { String($0.prefix(8)) } ?? "photo"
      let attachment = Attachment(
        name: "\(stem).\(prepared.fileExtension)",
        kind: .image, mime: prepared.mime,
        bytes: prepared.storage.count, thumbnail: prepared.thumbnail,
        ephemeral: !ui.mediaStoreByDefault,
        genTarget: .default(for: .image), analysisJPEG: prepared.analysis,
        original: prepared.storage
      )
      attachments.append(attachment)
    }
    processQueue()
  }

  /// Web `removeItem`: a kept asset leaves Storage together with its tray
  /// item; if that fails the item stays so the user can retry, exactly as the
  /// web keeps it. Items still in flight are dropped here and the worker
  /// cleans up after itself (see `process`).
  func remove(_ id: UUID) {
    guard let attachment = attachments.first(where: { $0.id == id }) else { return }
    guard let assetID = attachment.assetID, let path = attachment.storagePath,
          let profiles = env.profiles
    else {
      attachments.removeAll { $0.id == id }
      return
    }
    Task { [weak self] in
      do {
        try await profiles.deleteMediaAsset(id: assetID, storagePath: path)
        self?.attachments.removeAll { $0.id == id }
      } catch {
        self?.env.toasts.error(error.localizedDescription)
      }
    }
  }

  func setRole(_ role: AttachmentRole, for id: UUID) {
    guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
    attachments[index].role = role
    attachments[index].inserted = false
    // A role change between intent families re-analyzes.
    if let intent = role.analysisIntent, attachments[index].analyzedIntent != intent {
      attachments[index].status = .queued
      attachments[index].attrs = nil
      attachments[index].description = nil
      attachments[index].extractedText = nil
      processQueue()
    }
  }

  func setGenTarget(_ target: GenTarget, for id: UUID) {
    guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
    attachments[index].genTarget = target
  }

  /// Insert the attachment's payload into the draft: description / transcript
  /// / style snippet / a generation prompt built around the current draft.
  func insert(_ id: UUID) {
    guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
    let a = attachments[index]
    let snippet: String
    switch a.role {
    case .reference, .describe: snippet = a.description ?? ""
    case .extract: snippet = a.extractedText ?? ""
    case .style: snippet = a.attrs.map(MediaContext.styleSnippet) ?? ""
    case .generate:
      let attrs = a.attrs ?? MediaAttributes(description: a.description)
      let prior = ui.editorDraft
      ui.editorDraft = GenerationPrompt.build(
        base: ui.editorDraft,
        attrs: attrs,
        target: a.genTarget
      )
      attachments[index].inserted = true
      env.toasts
        .show("Generation prompt built", actionLabel: "Undo") { [ui] in ui.editorDraft = prior }
      return
    }
    guard !snippet.isEmpty else { return }
    let prior = ui.editorDraft
    ui.editorDraft = prior.isEmpty ? snippet : "\(prior)\n\n\(snippet)"
    attachments[index].inserted = true
    env.toasts.show("Inserted", actionLabel: "Undo") { [ui] in ui.editorDraft = prior }
  }

  /// Files process sequentially — kinder to the burst limiter and the cap.
  private func processQueue() {
    guard queueTask == nil else { return }
    queueTask = Task { [weak self] in
      defer { self?.queueTask = nil }
      while let self, let index = attachments.firstIndex(where: { $0.status == .queued }) {
        await process(index: index)
      }
    }
  }

  private func process(index: Int) async {
    guard let api = env.api, let profiles = env.profiles else { return }
    let id = attachments[index].id
    func patch(_ change: (inout Attachment) -> Void) {
      if let i = attachments.firstIndex(where: { $0.id == id }) {
        change(&attachments[i])
      }
    }
    var a = attachments[index]
    do {
      if !a.ephemeral, a.assetID == nil, let original = a.original {
        patch { $0.status = .reserving }
        let reserved = try await profiles.storeAttachment(
          data: original,
          name: a.name,
          mime: a.mime,
          kind: a.kind,
          role: a.role
        )
        guard attachments.contains(where: { $0.id == id }) else {
          // Removed while uploading: nothing invisible may keep charging quota.
          try? await profiles.deleteMediaAsset(id: reserved.id, storagePath: reserved.storage_path)
          return
        }
        patch {
          $0.assetID = reserved.id
          $0.storagePath = reserved.storage_path
        }
      }
      guard let intent = a.role.analysisIntent, let requestIntent = a.role.requestIntent,
            let jpeg = a.analysisJPEG
      else {
        patch { $0.status = .ready }
        return
      }
      let target = ui.targetModel
      patch {
        $0.status = .analyzing
        $0.analysisTarget = target
      }
      let response = try await api.analyze(
        MediaAnalysisRequest(
          dataUrl: MediaAnalysisRequest.dataURL(
            mime: "image/jpeg",
            base64: jpeg.base64EncodedString()
          ),
          target: target, intent: requestIntent, auto: ui.autoTarget,
          autoPreference: ui.autoPreference
        )
      )
      // The role may have changed while the request was in flight. A different
      // intent family means this payload is stale: leave the item queued so the
      // worker loop re-analyzes it, never mark it ready with the wrong result.
      guard let live = attachments.first(where: { $0.id == id }) else { return }
      guard live.role.analysisIntent == intent else {
        patch { $0.status = .queued }
        return
      }
      patch {
        $0.status = .ready
        $0.analyzedIntent = intent
        $0.usage = response.usage
        if intent == .extractText {
          $0.extractedText = response.text ?? ""
        } else {
          var attrs = response.attributes ?? MediaAttributes()
          attrs.description = response.description
          $0.attrs = attrs
          $0.description = response.description
        }
        $0.original = nil
      }
      if let fallback = response.fallbackFrom {
        let analyzedWith = response.usage.target?.label ?? response.modelUsed
        env.toasts.show("\(fallback.label) can't read images — analyzed with \(analyzedWith).")
      }
    } catch let failure as EnhanceFailure {
      patch { $0.status = .error(failure.displayMessage) }
    } catch {
      patch { $0.status = .error(error.localizedDescription) }
    }
  }
}

/// JPEG normalization for attachments: a bounded analysis copy for the
/// vision call, a thumbnail for the tray, and the original bytes for storage.
enum ImageProcessing {
  static let analysisMaxEdge: CGFloat = 1568
  static let thumbnailEdge: CGFloat = 160

  struct Prepared {
    var storage: Data
    var mime: String
    var fileExtension: String
    var analysis: Data?
    var thumbnail: Data?
  }

  /// Bytes that go to storage keep their ORIGINAL encoding and MIME when the
  /// `media` bucket already allows it (PNG/JPEG/WebP/GIF — an animated GIF
  /// must not be flattened); anything else (HEIC, unknown) is transcoded to
  /// JPEG and reported as such, so path, Content-Type and bytes always agree.
  static func prepare(_ data: Data, mime: String) -> Prepared {
    let image = UIImage(data: data)
    let allowed = MediaKind.kind(forMIME: mime) == .image
    let storage: Data
    let storageMime: String
    if allowed {
      storage = data
      storageMime = mime.lowercased()
    } else {
      storage = image?.jpegData(compressionQuality: 0.92) ?? data
      storageMime = "image/jpeg"
    }
    let analysis = image
      .flatMap { resized($0, maxEdge: analysisMaxEdge)?.jpegData(compressionQuality: 0.85) }
    let thumbnail = image
      .flatMap { resized($0, maxEdge: thumbnailEdge)?.jpegData(compressionQuality: 0.7) }
    return Prepared(
      storage: storage, mime: storageMime,
      fileExtension: MediaKind.fileExtension(forMIME: storageMime),
      analysis: analysis, thumbnail: thumbnail
    )
  }

  static func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage? {
    let size = image.size
    let scale = min(1, maxEdge / max(size.width, size.height))
    let target = CGSize(
      width: (size.width * scale).rounded(),
      height: (size.height * scale).rounded()
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }

  /// Square center-crop + resize for avatars.
  static func avatarPNG(_ data: Data, edge: CGFloat = 512) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let side = min(image.size.width, image.size.height)
    let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let cropped = UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format)
      .image { _ in
        let scale = edge / side
        image.draw(in: CGRect(
          x: -origin.x * scale,
          y: -origin.y * scale,
          width: image.size.width * scale,
          height: image.size.height * scale
        ))
      }
    return cropped.pngData()
  }
}
