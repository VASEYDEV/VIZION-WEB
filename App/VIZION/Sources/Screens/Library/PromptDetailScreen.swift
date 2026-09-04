import SwiftUI
import VizionCore

/// One saved prompt: title, tags, the current version, history with
/// restore + diff-any-two, and a revise pass that appends a version.
struct PromptDetailScreen: View {
  var promptID: String
  @Environment(AppEnvironment.self) private var env
  @State private var model: PromptDetailViewModel?

  var body: some View {
    Group {
      if let model {
        PromptDetailView(model: model)
      } else {
        ProgressView()
      }
    }
    .onAppear {
      if model == nil {
        let m = PromptDetailViewModel(env: env, promptID: promptID)
        model = m
        Task { await m.load() }
      }
    }
    .navigationTitle("")
    .toolbar(.visible, for: .navigationBar)
    .toolbarBackground(.hidden, for: .navigationBar)
  }
}

@MainActor
@Observable
final class PromptDetailViewModel {
  let env: AppEnvironment
  let promptID: String

  private(set) var head: PromptHead?
  private(set) var versions: [VersionMeta] = []
  private(set) var bodies: [String: VersionBody] = [:]
  private(set) var loading = true
  private(set) var error: String?

  var compareA: String?
  var compareB: String?

  var reviseDraft = ""
  var reviseMode: EnhanceMode = .clarify
  private(set) var stream: EnhanceStreamState = .idle
  private(set) var revising = false
  private(set) var revised: (input: String, mode: EnhanceMode, result: EnhanceResult)?
  var reviseError: EnhanceFailure?
  private var runTask: Task<Void, Never>?

  init(env: AppEnvironment, promptID: String) {
    self.env = env
    self.promptID = promptID
  }

  var currentID: String? {
    head?.current_ver ?? versions.last?.id
  }

  var current: VersionMeta? {
    versions.first { $0.id == currentID } ?? versions.last
  }

  var currentBody: VersionBody? {
    currentID.flatMap { bodies[$0] }
  }

  var target: TargetModel {
    head?.target ?? .default
  }

  func label(_ id: String) -> String {
    versions.firstIndex { $0.id == id }.map { "v\($0 + 1)" } ?? "v?"
  }

  func load() async {
    guard let library = env.library else { return }
    loading = true
    defer { loading = false }
    do {
      async let headTask = library.head(id: promptID)
      async let versionsTask = library.versions(promptID: promptID)
      let (head, versions) = try await (headTask, versionsTask)
      self.head = head
      self.versions = versions
      let current = head.current_ver ?? versions.last?.id
      if let current {
        await ensureBody(current)
      }
      if let body = current.flatMap({ bodies[$0] }), reviseDraft.isEmpty {
        reviseDraft = body.output_text
        reviseMode = current.flatMap { id in versions.first { $0.id == id } }
          .flatMap { EnhanceMode(rawValue: $0.mode) } ?? .clarify
      }
      compareB = current
      compareA = versions.first { $0.id == current }?.parent_ver ?? versions.dropLast().last?
        .id ?? current
      if let a = compareA {
        await ensureBody(a)
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  func ensureBody(_ id: String) async {
    guard bodies[id] == nil, let library = env.library else { return }
    if let body = try? await library
      .versionBody(promptID: promptID, versionID: id) {
      bodies[id] = body
    }
  }

  // MARK: Mutations

  private func mutate(_ work: () async throws -> Void) async {
    do {
      try await work()
      await load()
    } catch {
      env.toasts.error(error.localizedDescription)
    }
  }

  func rename(_ title: String) async {
    await mutate { try await env.library?.updateTitle(
      promptID: promptID,
      title: title
    ) }
  }

  func updateTags(_ raw: String) async {
    await mutate { try await env.library?.updateTags(
      promptID: promptID,
      tags: LibraryUtil.parseTags(raw)
    ) }
  }

  func restore(_ versionID: String) async {
    await mutate { try await env.library?.restoreVersion(promptID: promptID, versionID: versionID) }
    env.toasts.show("Restored \(label(versionID))")
  }

  func toggleFavorite() async {
    guard let head else { return }
    await mutate {
      try await env.library?.setFavorite(promptID: promptID, !(head.favorite ?? false))
    }
  }

  func softDelete() async -> Bool {
    do {
      try await env.library?.softDelete(promptID: promptID)
      env.toasts.show("Moved to Recently deleted", actionLabel: "Undo") { [env, promptID] in
        Task { try? await env.library?.undoDelete(promptID: promptID) }
      }
      return true
    } catch {
      env.toasts.error(error.localizedDescription)
      return false
    }
  }

  // MARK: Revise

  func revise() {
    guard let api = env.api else { return }
    let request = EnhanceRequest(input: reviseDraft, mode: reviseMode, target: target)
    if let invalid = request.validate() {
      reviseError = EnhanceFailure(message: invalid, status: 400)
      return
    }
    runTask?.cancel()
    reviseError = nil
    revised = nil
    stream = .started()
    revising = true
    runTask = Task { [weak self] in
      do {
        var done: EnhanceResult?
        for try await event in api.enhance(request) {
          guard let self else { return }
          if case let .error(status, message, notConfigured, capReached) = event {
            throw EnhanceFailure(
              message: message,
              status: status,
              notConfigured: notConfigured,
              capReached: capReached
            )
          }
          var state = stream
          state.apply(event)
          stream = state
          if case let .done(result) = event {
            done = result
          }
        }
        guard let self, let done else { return }
        revised = (request.input, request.mode, done)
      } catch let failure as EnhanceFailure {
        if !failure.isCancelled {
          self?.reviseError = failure
        }
      } catch {
        self?.reviseError = EnhanceFailure(message: error.localizedDescription, status: 502)
      }
      self?.revising = false
    }
  }

  func cancelRevise() {
    runTask?.cancel()
    revising = false
    stream = .idle
  }

  func saveRevision() async {
    guard let revised, let library = env.library else { return }
    let input = LibraryRepository.VersionInput(
      input: revised.input, output: revised.result.output, rationale: revised.result.rationale,
      mode: revised.mode,
      target: revised.result.resolvedTarget ?? target, modelUsed: revised.result.modelUsed,
      tokenIn: revised.result.tokenIn, tokenOut: revised.result.tokenOut, title: nil
    )
    do {
      _ = try await library.addVersion(promptID: promptID, input)
      self.revised = nil
      env.toasts.show("Saved as a new version")
      await load()
    } catch {
      env.toasts.error(error.localizedDescription)
    }
  }
}

struct PromptDetailView: View {
  @Bindable var model: PromptDetailViewModel
  @Environment(AppEnvironment.self) private var env
  @Environment(\.dismiss) private var dismiss
  @State private var renaming = false
  @State private var renameText = ""
  @State private var editingTags = false
  @State private var tagText = ""
  @State private var confirmDelete = false

  var body: some View {
    ScrollView {
      ScreenColumn(spacing: 20) {
        if let error = model.error {
          Text(error).font(.vzBody(13)).foregroundStyle(VZ.flare)
        } else if let head = model.head {
          header(head)
          currentPanel
          historyPanel
          comparePanel
          revisePanel
          VizionFooter()
        } else {
          ProgressView().tint(VZ.accent).frame(maxWidth: .infinity)
        }
      }
    }
    .alert("Rename", isPresented: $renaming) {
      TextField("Title", text: $renameText)
      Button("Save") { Task { await model.rename(renameText) } }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Tags", isPresented: $editingTags) {
      TextField("Comma separated", text: $tagText)
      Button("Save") { Task { await model.updateTags(tagText) } }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog(
      "Delete this prompt?",
      isPresented: $confirmDelete,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { Task {
        if await model.softDelete() {
          dismiss()
        }
      } }
    } message: {
      Text("It moves to Recently deleted, where you can restore it.")
    }
  }

  private func header(_ head: PromptHead) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        Text(head.title).font(.vzDisplay(28)).foregroundStyle(VZ.text)
        Spacer()
        Menu {
          Button { renameText = head.title; renaming = true } label: { Label(
            "Rename",
            systemImage: "pencil"
          ) }
          Button { tagText = head.tags.joined(separator: ", "); editingTags = true } label: { Label(
            "Edit tags",
            systemImage: "tag"
          ) }
          Button { Task { await model.toggleFavorite() } } label: {
            Label(head.favorite == true ? "Unfavorite" : "Favorite", systemImage: "star")
          }
          Button(role: .destructive) { confirmDelete = true } label: { Label(
            "Delete",
            systemImage: "trash"
          ) }
        } label: {
          Text("⋯").font(.vzBody(20)).foregroundStyle(VZ.muted).frame(width: 44, height: 44)
        }
      }
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          TargetMark(targetID: head.target_model, size: 13); Text(head.modelLabel)
        }
        .foregroundStyle(VZ.accent)
        ForEach(head.tags, id: \.self) { Text("#\($0)") }
        Text("\(model.versions.count) version\(model.versions.count == 1 ? "" : "s")")
      }
      .font(.vzBody(12)).foregroundStyle(VZ.muted)
    }
  }

  private var currentPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionCaption(text: "Current · \(model.currentID.map(model.label) ?? "")", icon: .check)
        Spacer()
        if let body = model.currentBody {
          Button {
            UIPasteboard.general.string = body.output_text
            env.toasts.show("Copied")
          } label: { IconView(.copy, size: 16) }.buttonStyle(.quiet)
          ShareLink(item: body.output_text) { IconView(.share, size: 16) }.buttonStyle(.quiet)
            .simultaneousGesture(TapGesture()
              .onEnded { Task { try? await env.library?.logShare(promptID: model.promptID) } })
        }
      }
      if let body = model.currentBody {
        Text(body.output_text).font(.vzMono(14)).foregroundStyle(VZ.text).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding(14)
          .vzGlassSolid(cornerRadius: VZ.Radius.control)
        if let rationale = body.rationale, !rationale.isEmpty {
          Text(rationale).font(.vzBody(13)).foregroundStyle(VZ.muted)
        }
      } else {
        ProgressView().tint(VZ.accent)
      }
    }
  }

  private var historyPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionCaption(text: "History", icon: .history)
      VStack(spacing: 0) {
        ForEach(model.versions.reversed()) { version in
          HStack(spacing: 10) {
            Text(model.label(version.id)).font(.vzBody(13, .semibold))
              .foregroundStyle(version.id == model.currentID ? VZ.accent : VZ.text)
            Text(version.modeLabel).font(.vzBody(12)).foregroundStyle(VZ.muted)
            Text(version.model_used).font(.vzBody(11)).foregroundStyle(VZ.muted).lineLimit(1)
            Spacer()
            Text(LibraryUtil.relativeTime(iso: version.created_at)).font(.vzBody(11))
              .foregroundStyle(VZ.muted)
            if version.id != model.currentID {
              Button("Restore") { Task { await model.restore(version.id) } }
                .buttonStyle(.secondaryInline)
            }
          }
          .padding(.horizontal, 14).padding(.vertical, 10)
          Rectangle().fill(VZ.hair).frame(height: 1)
        }
      }
      .vzGlass()
    }
  }

  private var comparePanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionCaption(text: "Compare", icon: .eye)
      HStack(spacing: 8) {
        versionPicker(
          "From",
          selection: Binding(
            get: { model.compareA },
            set: {
              model.compareA = $0; if let id = $0 {
                Task { await model.ensureBody(id) }
              }
            }
          )
        )
        versionPicker(
          "To",
          selection: Binding(
            get: { model.compareB },
            set: {
              model.compareB = $0; if let id = $0 {
                Task { await model.ensureBody(id) }
              }
            }
          )
        )
      }
      if let a = model.compareA.flatMap({ model.bodies[$0] }),
         let b = model.compareB.flatMap({ model.bodies[$0] }) {
        if a.id == b.id {
          Text("Pick two different versions.").font(.vzBody(12)).foregroundStyle(VZ.muted)
        } else if let diff = WordDiff.boundedDiffWords(a.output_text, b.output_text) {
          VStack(alignment: .leading, spacing: 6) {
            Text("\(WordDiff.countChangedSections(diff)) changes").font(.vzBody(11))
              .foregroundStyle(VZ.muted)
            DiffText(segments: diff, side: .output).font(.vzMono(13)).foregroundStyle(VZ.text)
              .frame(maxWidth: .infinity, alignment: .leading).padding(12).vzScrim()
          }
        } else {
          Text("Too long to diff.").font(.vzBody(12)).foregroundStyle(VZ.muted)
        }
      } else {
        ProgressView().tint(VZ.accent)
      }
    }
  }

  private func versionPicker(_ label: String, selection: Binding<String?>) -> some View {
    Menu {
      ForEach(model.versions) { v in
        Button(model.label(v.id)) { selection.wrappedValue = v.id }
      }
    } label: {
      HStack(spacing: 4) {
        Text(label).foregroundStyle(VZ.muted)
        Text(selection.wrappedValue.map(model.label) ?? "—")
        IconView(.chevronDown, size: 12)
      }
      .font(.vzBody(13, .medium)).foregroundStyle(VZ.text)
      .padding(.horizontal, 12).frame(minHeight: 36).vzGlass(cornerRadius: VZ.Radius.control)
    }
  }

  private var revisePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionCaption(text: "Revise", icon: .enhance)
      Text("Iterate on the current result with \(model.target.label); saving appends a version.")
        .font(.vzBody(12)).foregroundStyle(VZ.muted)
      ModeRigView(activeMode: $model.reviseMode)
      TextEditor(text: $model.reviseDraft).font(.vzBody(15)).foregroundStyle(VZ.text)
        .scrollContentBackground(.hidden).frame(minHeight: 120).padding(8)
        .vzGlassSolid(cornerRadius: VZ.Radius.control)
      if model.revising {
        StreamProgressView(stream: model.stream) { model.cancelRevise() }
      } else {
        Button("Run \(model.reviseMode.label)") { model.revise() }.buttonStyle(.laser)
          .disabled(model.reviseDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if let error = model
        .reviseError {
        Text(error.displayMessage).font(.vzBody(13)).foregroundStyle(VZ.flare)
      }
      if let revised = model.revised {
        VStack(alignment: .leading, spacing: 8) {
          if let diff = revised.result.diff {
            DiffText(segments: diff, side: .output)
          } else {
            Text(revised.result.output)
          }
          HStack {
            Button("Save as version") { Task { await model.saveRevision() } }
              .buttonStyle(.laserInline)
            Button("Copy") {
              UIPasteboard.general.string = revised.result.output
              env.toasts.show("Copied")
            }.buttonStyle(.secondaryInline)
          }
          let stats = revised.result
          let cost = String(format: "%.4f", stats.costUsd)
          Text("\(stats.tokenIn)→\(stats.tokenOut) tok · $\(cost) · \(stats.modelUsed)")
            .font(.vzBody(11)).monospacedDigit().foregroundStyle(VZ.muted)
        }
        .font(.vzMono(13)).foregroundStyle(VZ.text)
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .vzGlassSolid(cornerRadius: VZ.Radius.control)
      }
    }
  }
}
