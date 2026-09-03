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
  /// A refinement is a run over the CURRENT result; the chips show a spinner.
  private(set) var refinePending = false

  /// The `?draft=` offer when the editor already held work — no timer, stays
  /// until answered; replacing is undoable.
  var draftOffer: String?

  var attachments: [Attachment] = []
  var pendingPick: [PhotosPickerItem] = []
  var showPrivacyNotice = false
  private var queueTask: Task<Void, Never>?

  init(env: AppEnvironment) {
    self.env = env
  }

  var ui: UIStore { env.ui }
  var view: EnhanceView? { env.results.view }

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

  func discardDraftOffer() { draftOffer = nil }

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
  func clear() {
    let priorDraft = ui.editorDraft
    let priorView = view
    let priorAttachments = attachments
    cancel()
    ui.editorDraft = ""
    attachments = []
    env.results.set(nil, userID: env.session?.userID)
    error = nil
    if !priorDraft.isEmpty || priorView != nil {
      env.toasts.show("Cleared", actionLabel: "Undo") { [weak self] in
        guard let self else { return }
        ui.editorDraft = priorDraft
        attachments = priorAttachments
        env.results.set(priorView, userID: env.session?.userID)
      }
    }
  }

  // MARK: Run

  var tokenEstimate: Int { EnhanceStreamState.estimateTokens(chars: ui.editorDraft.utf16.count) }

  var contextBlocks: [String] {
    MediaContext.build(attachments.map {
      MediaContextItem(role: $0.role, isReady: $0.status == .ready, name: $0.name, description: $0.description, attrs: $0.attrs)
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
      input: request.input, mode: request.mode, target: request.target, format: request.format, length: request.length)
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
      thinkingLevel: ui.thinkingLevels[view.effectiveTarget].flatMap { view.effectiveTarget.thinkingLadder.contains($0) ? $0 : nil },
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
      refine: EnhanceRefine(kind: .answers, baseInput: EnhanceRefine.answersBlock(questions: questions, answers: answers))
    )
    start(request, submitted: view.submitted, refined: false)
  }

  private func start(_ request: EnhanceRequest, submitted: EnhanceView.Submitted, refined: Bool) {
    guard let api = env.api else { return }
    runTask?.cancel()
    error = nil
    stream = .started()
    isRunning = true
    let userID = env.session?.userID
    runTask = Task { [weak self] in
      var pendingText = ""
      var lastFlush = ContinuousClock.now
      func flush(_ state: inout EnhanceStreamState) {
        guard !pendingText.isEmpty else { return }
        state.apply(.delta(text: pendingText))
        pendingText = ""
        lastFlush = .now
      }
      do {
        var done: EnhanceResult?
        for try await event in api.enhance(request) {
          guard let self else { return }
          switch event {
          case let .delta(text):
            // Batch deltas so the editor doesn't re-render per token.
            pendingText += text
            if ContinuousClock.now - lastFlush > .milliseconds(40) {
              var state = stream
              flush(&state)
              stream = state
            }
          case let .error(status, message, notConfigured, capReached):
            throw EnhanceFailure(message: message, status: status, notConfigured: notConfigured, capReached: capReached)
          case let .done(result):
            done = result
            var state = stream
            flush(&state)
            state.apply(event)
            stream = state
          default:
            var state = stream
            flush(&state)
            state.apply(event)
            stream = state
          }
        }
        guard let self else { return }
        var state = stream
        flush(&state)
        stream = state
        guard let done else { throw EnhanceFailure(message: "The stream ended unexpectedly.", status: 502) }
        env.results.set(EnhanceView(submitted: submitted, result: done, refined: refined ? true : nil, rejected: nil), userID: userID)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch let failure as EnhanceFailure {
        if !failure.isCancelled { self?.error = failure }
      } catch {
        if !(error is CancellationError) {
          self?.error = EnhanceFailure(message: error.localizedDescription, status: 502)
        }
      }
      guard let self else { return }
      isRunning = false
      refinePending = false
      var state = stream
      state.active = false
      stream = state
    }
  }

  func cancel() {
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
    env.toasts.show("Result moved into the editor", actionLabel: "Undo") { [ui] in ui.editorDraft = prior }
  }

  func setRejected(_ rejected: Set<Int>) {
    env.results.update { $0.rejected = rejected.isEmpty ? nil : rejected.sorted() }
  }

  func versionInput(title: String? = nil) -> LibraryRepository.VersionInput? {
    guard let view else { return nil }
    return LibraryRepository.VersionInput(
      input: view.submitted.input, output: view.effectiveOutput, rationale: view.result.rationale,
      mode: view.submitted.mode, target: view.effectiveTarget, modelUsed: view.result.modelUsed,
      tokenIn: view.result.tokenIn, tokenOut: view.result.tokenOut, title: title ?? view.result.title
    )
  }

  func exportData() -> ExportData? {
    guard let view else { return nil }
    return ExportData(
      input: view.submitted.input, output: view.effectiveOutput, rationale: view.result.rationale,
      mode: view.submitted.mode, target: view.effectiveTarget, modelUsed: view.result.modelUsed
    )
  }

  // MARK: Attachments

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
    /// Downscaled JPEG for the vision call; dropped once analysis finishes.
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

  private func enqueue(_ items: [PhotosPickerItem]) async {
    for item in items {
      guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
      let type = item.supportedContentTypes.first
      let mime = type?.preferredMIMEType ?? "image/jpeg"
      let isImage = type?.conforms(to: .image) ?? true
      guard isImage else {
        env.toasts.error("Only images are supported on iOS for now.")
        continue
      }
      let normalized = ImageProcessing.normalize(data)
      let attachment = Attachment(
        name: item.itemIdentifier.map { "\($0.prefix(8)).jpg" } ?? "photo.jpg",
        kind: .image, mime: MediaKind.kind(forMIME: mime) != nil ? mime : "image/jpeg",
        bytes: normalized.original.count, thumbnail: normalized.thumbnail, ephemeral: !ui.mediaStoreByDefault,
        genTarget: .default(for: .image), analysisJPEG: normalized.analysis, original: normalized.original
      )
      attachments.append(attachment)
    }
    processQueue()
  }

  func remove(_ id: UUID) {
    attachments.removeAll { $0.id == id }
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
      ui.editorDraft = GenerationPrompt.build(base: ui.editorDraft, attrs: attrs, target: a.genTarget)
      attachments[index].inserted = true
      env.toasts.show("Generation prompt built", actionLabel: "Undo") { [ui] in ui.editorDraft = prior }
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
      if let i = attachments.firstIndex(where: { $0.id == id }) { change(&attachments[i]) }
    }
    var a = attachments[index]
    do {
      if !a.ephemeral, a.assetID == nil, let original = a.original {
        patch { $0.status = .reserving }
        let reserved = try await profiles.storeAttachment(data: original, name: a.name, mime: a.mime, kind: a.kind, role: a.role)
        patch {
          $0.assetID = reserved.id
          $0.storagePath = reserved.storage_path
        }
      }
      guard let intent = a.role.analysisIntent, let jpeg = a.analysisJPEG else {
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
          dataUrl: MediaAnalysisRequest.dataURL(mime: "image/jpeg", base64: jpeg.base64EncodedString()),
          target: target, intent: intent, auto: ui.autoTarget, autoPreference: ui.autoPreference
        ))
      a = attachments.first { $0.id == id } ?? a
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
        $0.analysisJPEG = nil
        $0.original = nil
      }
      if let fallback = response.fallbackFrom {
        env.toasts.show("\(fallback.label) can't read images — analyzed with \(response.usage.target?.label ?? response.modelUsed).")
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
  static let analysisMaxEdge: CGFloat = 1_568
  static let thumbnailEdge: CGFloat = 160

  struct Output {
    var original: Data
    var analysis: Data?
    var thumbnail: Data?
  }

  static func normalize(_ data: Data) -> Output {
    guard let image = UIImage(data: data) else { return Output(original: data) }
    let analysis = resized(image, maxEdge: analysisMaxEdge)?.jpegData(compressionQuality: 0.85)
    let thumbnail = resized(image, maxEdge: thumbnailEdge)?.jpegData(compressionQuality: 0.7)
    // HEIC from the picker transcodes to JPEG so the `media` bucket accepts it.
    let original = data.count > 0 && UIImage(data: data) != nil ? (image.jpegData(compressionQuality: 0.92) ?? data) : data
    return Output(original: original, analysis: analysis, thumbnail: thumbnail)
  }

  static func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage? {
    let size = image.size
    let scale = min(1, maxEdge / max(size.width, size.height))
    let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
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
    let cropped = UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format).image { _ in
      let scale = edge / side
      image.draw(in: CGRect(x: -origin.x * scale, y: -origin.y * scale, width: image.size.width * scale, height: image.size.height * scale))
    }
    return cropped.pngData()
  }
}
