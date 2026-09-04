import Combine
import SwiftUI
import VizionCore

/// The enhance result (web: `TransformationDiff`), mobile-first: Enhanced
/// leads, Copy + Use are the primary actions, the original collapses, and
/// Polish offers per-change accept/reject.
struct ResultView: View {
  var view: EnhanceView
  @Bindable var model: EnhanceViewModel
  @Binding var showSave: Bool

  @Environment(AppEnvironment.self) private var env
  @State private var showOriginal = false
  @State private var showReview = false
  @State private var answers: [String] = []
  @State private var savedID: String?

  private var result: EnhanceResult {
    view.result
  }

  private var hunks: [WordDiff.Hunk] {
    result.diff.map(WordDiff.hunks) ?? []
  }

  private var reviewable: Bool {
    view.submitted.mode == .polish && !hunks.isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      outputPanel
      primaryActions
      meta
      if result.truncated == true {
        note(
          "The model hit its output ceiling — this result is incomplete.",
          tone: VZ.amberInk
        )
      }
      if result.salvaged == true {
        note(
          "Recovered from a malformed response; the explanation was lost.",
          tone: VZ.muted
        )
      }
      if !result.rationale.isEmpty {
        section("What changed") { Text(result.rationale) }
      }
      if let assumptions = result.assumptions, !assumptions.isEmpty {
        section("Assumptions") {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(assumptions, id: \.self) { Text("• \($0)") }
          }
        }
      }
      if let notes = result.targetNotes,
         !notes.isEmpty {
        section("For \(view.effectiveTarget.label)") { Text(notes) }
      }
      if let questions = result.questions, !questions.isEmpty {
        questionsCard(questions)
      }
      refineChips
      if reviewable {
        reviewPanel
      }
      originalPanel
    }
    .padding(16)
    .vzGlass()
    .onAppear { answers = Array(repeating: "", count: result.questions?.count ?? 0) }
    .onChange(of: view.result) { _, _ in
      answers = Array(repeating: "", count: result.questions?.count ?? 0)
      savedID = nil
    }
    // Polish review decisions change `effectiveOutput` without a new result;
    // what was saved is then no longer what is shown.
    .onChange(of: view.rejected) { _, _ in
      savedID = nil
    }
  }

  // MARK: Pieces

  private var header: some View {
    HStack(spacing: 8) {
      SectionCaption(text: view.refined == true ? "Refined" : "Enhanced", icon: .sparkle)
      Spacer()
      HStack(spacing: 6) {
        DeveloperIcon(developer: view.effectiveTarget.developer, size: 14)
        Text(view.effectiveTarget.label)
        if let reason = result.resolvedReasonLabel, result.resolvedTarget != nil {
          Text("· Auto, \(reason)").foregroundStyle(VZ.muted)
        }
      }
      .font(.vzBody(12, .medium))
      .foregroundStyle(VZ.accent)
    }
  }

  private var outputPanel: some View {
    Group {
      if let diff = result.diff, !diff.isEmpty {
        DiffText(
          segments: diff,
          side: .output,
          rejected: view.rejectedSet,
          hunkIDs: WordDiff.assignHunks(diff)
        )
      } else {
        Text(view.effectiveOutput)
      }
    }
    .font(.vzMono(14))
    .foregroundStyle(VZ.text)
    .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .vzGlassSolid(cornerRadius: VZ.Radius.control)
  }

  private var primaryActions: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button { model.copyOutput() } label: {
          HStack(spacing: 6) { IconView(.copy, size: 16); Text("Copy") }
        }
        .buttonStyle(.laser)
        Button { model.useAsDraft() } label: {
          HStack(spacing: 6) { IconView(.paste, size: 16); Text("Use") }
        }
        .buttonStyle(.secondary)
      }
      HStack(spacing: 10) {
        if let savedID {
          Button {
            env.pendingPromptID = savedID
          } label: {
            HStack(spacing: 6) { IconView(.check, size: 16); Text("Saved — open") }
          }
          .buttonStyle(.secondary)
        } else {
          Button { showSave = true } label: { HStack(spacing: 6) { IconView(
            .library,
            size: 16
          ); Text("Save") } }
            .buttonStyle(.secondary)
        }
        ShareLink(item: view.effectiveOutput) {
          HStack(spacing: 6) { IconView(.share, size: 16); Text("Share") }
        }
        .buttonStyle(.secondary)
        .simultaneousGesture(TapGesture().onEnded {
          if let savedID {
            Task { try? await env.library?.logShare(promptID: savedID) }
          }
        })
        exportMenu
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .vizionPromptSaved)) { note in
      if let id = note.object as? String {
        savedID = id
      }
    }
  }

  private var exportMenu: some View {
    Menu {
      if let data = model.exportData() {
        ForEach(ExportFormat.allCases) { format in
          ShareLink(
            item: ExportFile(text: format.render(data), format: format),
            preview: SharePreview("VIZION export.\(format.fileExtension)")
          ) {
            Label(format.label, systemImage: "doc")
          }
        }
      }
    } label: {
      HStack(spacing: 6) { IconView(.share, size: 16); Text("Export") }
    }
    .buttonStyle(.secondaryInline)
  }

  private var meta: some View {
    HStack(spacing: 6) {
      Text("\(result.usageEstimated == true ? "≈" : "")\(result.tokenIn)→\(result.tokenOut) tok")
      Text("·")
      Text(String(format: "$%.4f", result.costUsd))
      Text("·")
      Text(result.modelUsed).lineLimit(1)
      if let diff = result.diff {
        Text("·")
        Text("\(WordDiff.countChangedSections(diff)) changes")
      }
    }
    .font(.vzBody(11)).monospacedDigit().foregroundStyle(VZ.muted)
  }

  private func note(_ text: String, tone: Color) -> some View {
    Text(text).font(.vzBody(12)).foregroundStyle(tone).frame(
      maxWidth: .infinity,
      alignment: .leading
    )
  }

  private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).vzCaps()
      content().font(.vzBody(14)).foregroundStyle(VZ.text).frame(
        maxWidth: .infinity,
        alignment: .leading
      )
    }
  }

  private func questionsCard(_ questions: [String]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("A few questions would sharpen this").vzCaps()
      ForEach(Array(questions.enumerated()), id: \.offset) { i, question in
        VStack(alignment: .leading, spacing: 4) {
          Text(question).font(.vzBody(14, .medium)).foregroundStyle(VZ.text)
          TextField("Your answer", text: Binding(
            get: { i < answers.count ? answers[i] : "" },
            set: {
              if i < answers.count {
                answers[i] = $0
              }
            }
          ))
          .vzInputFont().vzField()
        }
      }
      let answered = answers.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
      Button("Answer & re-run (\(answered)/\(questions.count))") {
        model.answer(questions: questions, answers: answers)
      }
      .buttonStyle(.laser)
      .disabled(answered == 0 || model.isRunning)
    }
    .padding(12)
    .vzScrim()
  }

  private var refineChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(RefineKind.chips) { kind in
          Button { model.refine(kind) } label: {
            ChipLabel(text: kind.chipLabel ?? kind.rawValue, selected: false, icon: .refresh)
          }
          .buttonStyle(.pressable)
          .disabled(model.isRunning)
        }
      }
    }
  }

  private var reviewPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation(VZ.Motion.quickAnimation) { showReview.toggle() }
      } label: {
        HStack {
          SectionCaption(text: "Review \(hunks.count) changes", icon: .eye)
          Spacer()
          IconView(showReview ? .chevronDown : .chevronRight, size: 14)
        }
      }
      .buttonStyle(.plain)
      if showReview {
        ForEach(hunks) { hunk in
          let rejected = view.rejectedSet.contains(hunk.index)
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text(hunk.removed.trimmingCharacters(in: .whitespacesAndNewlines))
                .strikethrough().foregroundStyle(VZ.muted)
              Text(hunk.added.trimmingCharacters(in: .whitespacesAndNewlines))
                .foregroundStyle(rejected ? VZ.muted : VZ.accent)
            }
            .font(.vzMono(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(rejected ? "Keep" : "Revert") {
              var next = view.rejectedSet
              if rejected {
                next.remove(hunk.index)
              } else {
                next.insert(hunk.index)
              }
              model.setRejected(next)
            }
            .buttonStyle(.secondaryInline)
          }
          .padding(8)
          .vzScrim()
        }
      }
    }
  }

  private var originalPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation(VZ.Motion.quickAnimation) { showOriginal.toggle() }
      } label: {
        HStack {
          SectionCaption(
            text: view.refined == true ? "Previous result" : "Original",
            icon: .history
          )
          Spacer()
          IconView(showOriginal ? .chevronDown : .chevronRight, size: 14)
        }
      }
      .buttonStyle(.plain)
      if showOriginal {
        Group {
          if let diff = result.diff, !diff.isEmpty {
            DiffText(
              segments: diff,
              side: .input,
              rejected: view.rejectedSet,
              hunkIDs: WordDiff.assignHunks(diff)
            )
          } else {
            Text(view.submitted.input)
          }
        }
        .font(.vzBody(14))
        .foregroundStyle(VZ.muted)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .vzScrim()
      }
    }
  }
}

/// One side of the transformation diff as attributed text: added tokens in
/// the accent on the output side, removed tokens struck through on the input side.
struct DiffText: View {
  enum Side { case input, output }
  var segments: [DiffSegment]
  var side: Side
  var rejected: Set<Int> = []
  var hunkIDs: [Int?] = []

  var body: some View {
    Text(attributed)
  }

  private var attributed: AttributedString {
    var out = AttributedString()
    for (i, seg) in segments.enumerated() {
      let isRejected = (i < hunkIDs.count ? hunkIDs[i] : nil).map { rejected.contains($0) } ?? false
      switch (seg.op, side) {
      case (.equal, _):
        out += AttributedString(seg.text)
      case (.added, .output):
        var piece = AttributedString(seg.text)
        if isRejected {
          piece.strikethroughStyle = .single
          piece.foregroundColor = VZ.muted
        } else {
          piece.foregroundColor = VZ.accent
          piece.underlineStyle = .single
        }
        out += piece
      case (.removed, .output):
        if isRejected {
          var piece = AttributedString(seg.text)
          piece.foregroundColor = VZ.text
          out += piece
        }
      case (.removed, .input):
        var piece = AttributedString(seg.text)
        piece.strikethroughStyle = .single
        piece.foregroundColor = VZ.flare
        out += piece
      case (.added, .input):
        break
      }
    }
    return out
  }
}

/// Save sheet: title (seeded from the model's suggestion) + tags, with the
/// duplicate offer ("Save as new version").
struct SavePromptSheet: View {
  @Bindable var model: EnhanceViewModel
  @Environment(AppEnvironment.self) private var env
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var tags = ""
  @State private var saving = false
  @State private var error: String?
  @State private var duplicate: (id: String, title: String)?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Save to library").font(.vzDisplay(26)).foregroundStyle(VZ.text)
      TextField("Title", text: $title).vzInputFont().vzField()
      TextField("Tags, comma separated", text: $tags).vzInputFont().vzField()
        .textInputAutocapitalization(.never)
      if let duplicate {
        VStack(alignment: .leading, spacing: 8) {
          Text("This is already in your library as “\(duplicate.title)”.").font(.vzBody(13))
            .foregroundStyle(VZ.muted)
          Button("Save as new version") { Task { await addVersion(to: duplicate.id) } }
            .buttonStyle(.secondary)
        }
      }
      if let error {
        Text(error).font(.vzBody(13)).foregroundStyle(VZ.flare)
      }
      Button(saving ? "Saving…" : "Save") { Task { await save() } }
        .buttonStyle(.laser).disabled(saving)
      Button("Cancel") { dismiss() }.buttonStyle(.quiet)
    }
    .padding(24)
    .onAppear {
      title = model.view?.result.title ?? LibraryUtil.deriveTitle(model.view?.submitted.input ?? "")
    }
    .vzSheet(detents: [.medium, .large])
  }

  private func save() async {
    guard let library = env.library, let input = model.versionInput(title: title) else { return }
    saving = true
    defer { saving = false }
    do {
      let id = try await library.savePrompt(input, title: title, tags: LibraryUtil.parseTags(tags))
      NotificationCenter.default.post(name: .vizionPromptSaved, object: id)
      env.toasts.show("Saved to your library")
      dismiss()
    } catch let failure as LibraryRepository.Failure {
      if case let .duplicate(promptID, dupTitle) = failure {
        duplicate = (promptID, dupTitle)
      } else {
        error = failure.localizedDescription
      }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func addVersion(to promptID: String) async {
    guard let library = env.library, let input = model.versionInput() else { return }
    saving = true
    defer { saving = false }
    do {
      _ = try await library.addVersion(promptID: promptID, input)
      NotificationCenter.default.post(name: .vizionPromptSaved, object: promptID)
      env.toasts.show("Saved as a new version")
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

extension Notification.Name {
  static let vizionPromptSaved = Notification.Name("vizion.promptSaved")
}

/// A text export handed to the share sheet as a file.
struct ExportFile: Transferable {
  var text: String
  var format: ExportFormat

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .plainText) { file in Data(file.text.utf8) }
      .suggestedFileName { "vizion-export.\($0.format.fileExtension)" }
  }
}
