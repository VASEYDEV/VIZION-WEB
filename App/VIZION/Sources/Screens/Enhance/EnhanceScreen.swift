import PhotosUI
import SwiftUI
import VizionCore

/// Enhance screen — the composer (modes · editor · attachments · target ·
/// result). Media attachment lives INSIDE the composer's tray.
struct EnhanceScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var model: EnhanceViewModel?

  var body: some View {
    Group {
      if let model {
        EnhanceComposer(model: model)
      } else {
        ProgressView()
      }
    }
    .onAppear { if model == nil { model = EnhanceViewModel(env: env) } }
  }
}

struct EnhanceComposer: View {
  @Bindable var model: EnhanceViewModel
  @Environment(AppEnvironment.self) private var env
  @State private var showTargets = false
  @State private var showThinking = false
  @State private var showTemplates = false
  @State private var showSave = false
  @FocusState private var editorFocused: Bool

  private var ui: UIStore { env.ui }

  var body: some View {
    @Bindable var ui = env.ui
    ScrollView {
      VStack(spacing: 0) {
        ScreenHeader(brand: true) {
          if !ui.editorDraft.isEmpty || model.view != nil {
            Button { model.clear() } label: { IconView(.close, size: 20) }
              .buttonStyle(.quiet)
              .accessibilityLabel("Clear")
          }
        }
        ScreenColumn(spacing: 24) {
          if let offer = model.draftOffer { draftOfferBanner(offer) }
          if let view = model.view, view.result.capFraction >= 0.8 { capBanner(view.result) }
          ModeRigView(activeMode: $ui.activeMode)
          composer
          if !model.attachments.isEmpty { AttachmentTrayView(model: model) }
          rails
          runControls
          if let view = model.view, !model.isRunning {
            ResultView(view: view, model: model, showSave: $showSave)
          }
          VizionFooter()
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .onAppear { model.consumePendingDraft() }
    .onChange(of: env.pendingDraft) { _, _ in model.consumePendingDraft() }
    .sheet(isPresented: $showTargets) {
      TargetPickerSheet(
        selection: $ui.targetModel, auto: $ui.autoTarget, autoPreference: $ui.autoPreference,
        autoDescription: "Picks the model per run from what's configured — quality, balanced, or budget."
      )
    }
    .sheet(isPresented: $showThinking) { ThinkingDialSheet(target: ui.targetModel, level: $ui.thinkingLevel) }
    .sheet(isPresented: $showTemplates) {
      TemplateSheet { template in
        model.apply(template: template)
        showTemplates = false
      }
    }
    .sheet(isPresented: $showSave) { SavePromptSheet(model: model) }
    .sheet(isPresented: $model.showPrivacyNotice) { MediaPrivacySheet(model: model) }
  }

  // MARK: Composer chassis

  private var composer: some View {
    VStack(spacing: 10) {
      ZStack(alignment: .topLeading) {
        if ui.editorDraft.isEmpty {
          Text("Paste or write a prompt…")
            .font(.vzBody(16))
            .foregroundStyle(VZ.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }
        TextEditor(text: Binding(get: { ui.editorDraft }, set: { ui.editorDraft = $0 }))
          .font(.vzBody(16))
          .foregroundStyle(VZ.text)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 160)
          .focused($editorFocused)
          .accessibilityLabel("Prompt")
      }
      HStack(spacing: 8) {
        Text("\(ui.editorDraft.utf16.count) chars · ~\(model.tokenEstimate) tok")
          .font(.vzBody(11)).monospacedDigit().foregroundStyle(VZ.muted)
        if ui.editorDraft.utf16.count > EnhanceRequest.maxInputChars {
          Text("over the \(EnhanceRequest.maxInputChars) limit").font(.vzBody(11)).foregroundStyle(VZ.flare)
        }
        Spacer()
        if ui.editorDraft.isEmpty {
          Button { model.paste() } label: { HStack(spacing: 4) { IconView(.paste, size: 14); Text("Paste") } }
            .buttonStyle(.quiet)
          Button { showTemplates = true } label: { HStack(spacing: 4) { IconView(.sparkle, size: 14); Text("Templates") } }
            .buttonStyle(.quiet)
        }
        PhotosPicker(selection: $model.pendingPick, maxSelectionCount: 4, matching: .images) {
          HStack(spacing: 4) { IconView(.paperclip, size: 14); Text("Attach") }
        }
        .buttonStyle(.quiet)
        .onChange(of: model.pendingPick) { _, items in
          guard !items.isEmpty, !model.showPrivacyNotice else { return }
          Task {
            await model.handlePicked(items)
            if !model.showPrivacyNotice { model.pendingPick = [] }
          }
        }
      }
      .font(.vzBody(12))
    }
    .padding(12)
    .vzGlassSolid()
  }

  // MARK: Rails

  private var rails: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        Button { showTargets = true } label: {
          HStack(spacing: 8) {
            if ui.autoTarget {
              IconView(.sparkle, size: 16)
              Text("Auto · \(ui.autoPreference.label)")
            } else {
              DeveloperIcon(developer: ui.targetModel.developer, size: 16)
              Text(ui.targetModel.label)
            }
            IconView(.chevronDown, size: 14)
          }
          .lineLimit(1)
        }
        .buttonStyle(.secondaryInline)
        .accessibilityLabel("Target model")

        if !ui.autoTarget, ui.targetModel.hasThinkingDial {
          Button { showThinking = true } label: {
            HStack(spacing: 6) {
              DepthMeter(level: ui.thinkingLevel, ladder: ui.targetModel.thinkingLadder)
              Text(ui.thinkingLevel?.label ?? "Auto")
                .foregroundStyle(ui.thinkingLevel?.tone == .ultra ? VZ.ultra : VZ.text)
            }
          }
          .buttonStyle(.secondaryInline)
          .accessibilityLabel("Thinking depth")
        }
        Spacer(minLength: 0)
      }

      if ui.activeMode == .reformat {
        railRow("Shape") {
          VZSegmented(
            options: OutputFormat.allCases.map { (id: $0, label: $0.label) },
            selection: Binding(get: { ui.reformatFormat }, set: { ui.reformatFormat = $0 }),
            fill: true, clearsOnReselect: true, accessibilityLabel: "Output shape"
          )
        }
      } else if let options = ui.activeMode.lengthOptions {
        railRow("Depth") {
          VZSegmented(
            options: options.map { (id: $0.id, label: $0.label) },
            selection: Binding(get: { ui.lengthForActiveMode }, set: { ui.lengthForActiveMode = $0 }),
            fill: true, clearsOnReselect: true, accessibilityLabel: "Length"
          )
        }
      }

      if ui.activeMode.isShapePreserving, !ui.autoTarget {
        Text("\(ui.activeMode.label) keeps your prompt's shape — the model only affects routing and cost.")
          .font(.vzBody(11)).foregroundStyle(VZ.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func railRow(_ caption: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(caption).vzCaps()
      content()
    }
  }

  // MARK: Run

  private var runControls: some View {
    VStack(spacing: 12) {
      if model.isRunning {
        StreamProgressView(stream: model.stream) { model.cancel() }
      } else {
        Button {
          editorFocused = false
          model.run()
        } label: {
          HStack(spacing: 8) {
            IconView(.enhance, size: 18)
            Text(model.view == nil ? "Enhance" : "Enhance again")
          }
        }
        .buttonStyle(.laser)
        .disabled(ui.editorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if let error = model.error, !error.isCancelled {
        VStack(alignment: .leading, spacing: 6) {
          Text(error.displayMessage)
            .font(.vzBody(13)).foregroundStyle(VZ.flare)
          if error.capReached {
            Text("It resets at midnight UTC.").font(.vzBody(12)).foregroundStyle(VZ.muted)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .vzScrim()
      }
    }
  }

  private func draftOfferBanner(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("A prompt arrived while you had work in progress").font(.vzBody(14, .medium)).foregroundStyle(VZ.text)
      Text(text).font(.vzBody(13)).foregroundStyle(VZ.muted).lineLimit(4)
      HStack {
        Button("Replace draft") { model.acceptDraftOffer() }.buttonStyle(.laserInline)
        Button("Discard it") { model.discardDraftOffer() }.buttonStyle(.secondaryInline)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .vzGlass()
  }

  private func capBanner(_ result: EnhanceResult) -> some View {
    HStack(spacing: 10) {
      Circle().fill(VZ.amber).frame(width: 8, height: 8)
      Text(
        result.capFraction >= 1
          ? "You've reached today's usage cap ($\(result.usage.capUsd, specifier: "%.2f")). It resets at midnight UTC."
          : "Today's usage: $\(result.usage.todayCost, specifier: "%.2f") of $\(result.usage.capUsd, specifier: "%.2f")."
      )
      .font(.vzBody(12)).foregroundStyle(VZ.amberInk)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .vzScrim()
  }
}

/// Mode instrument: ONE glass chassis with six equal cells, icon-over-label,
/// and a sliding Laser lens behind the active cell. A one-line blurb below.
struct ModeRigView: View {
  @Binding var activeMode: EnhanceMode
  @Namespace private var lens

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 0) {
        ForEach(EnhanceMode.allCases) { mode in
          let active = mode == activeMode
          Button {
            withAnimation(VZ.Motion.slideAnimation) { activeMode = mode }
            UISelectionFeedbackGenerator().selectionChanged()
          } label: {
            VStack(spacing: 4) {
              IconView(.mode(mode), size: 20)
                .foregroundStyle(active ? VZ.onLaser : VZ.accent)
              Text(mode.label)
                .font(.vzBody(10, .medium, relativeTo: .caption2))
                .tracking(-0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(active ? VZ.onLaser : VZ.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
              if active {
                RoundedRectangle(cornerRadius: VZ.Radius.control, style: .continuous)
                  .fill(VZ.laser)
                  .matchedGeometryEffect(id: "lens", in: lens)
              }
            }
          }
          .buttonStyle(.pressable)
          .accessibilityAddTraits(active ? .isSelected : [])
          .accessibilityLabel(mode.label)
          .accessibilityHint(mode.blurb)
        }
      }
      .padding(4)
      .vzGlass()
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Enhancement mode")

      Text(activeMode.blurb)
        .font(.vzBody(12))
        .foregroundStyle(VZ.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .vzScrim()
        .animation(VZ.Motion.quickAnimation, value: activeMode)
    }
  }
}

/// Filled bars showing the chosen depth on the target's own ladder.
struct DepthMeter: View {
  var level: ThinkingLevel?
  var ladder: [ThinkingLevel]

  var body: some View {
    let filled = level.flatMap { ladder.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(0..<max(ladder.count, 1), id: \.self) { i in
        RoundedRectangle(cornerRadius: 1)
          .fill(i < filled ? (level?.tone == .ultra ? VZ.ultra : VZ.muted) : VZ.muted.opacity(0.25))
          .frame(width: 3, height: 5 + CGFloat(i) * 2)
      }
    }
    .frame(height: 14, alignment: .bottom)
  }
}

/// Live progress while a run is in flight: step label, partial output, and
/// the monotonic token/cost ticker.
struct StreamProgressView: View {
  var stream: EnhanceStreamState
  var onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView().tint(VZ.accent).controlSize(.small)
        Text(stream.step).font(.vzBody(13, .medium)).foregroundStyle(VZ.text)
        Spacer()
        Text(ticker).font(.vzBody(11)).monospacedDigit().foregroundStyle(VZ.muted)
        Button("Cancel", action: onCancel).buttonStyle(.quiet)
      }
      if !stream.partialOutput.isEmpty {
        ScrollView {
          Text(stream.partialOutput)
            .font(.vzMono(13))
            .foregroundStyle(VZ.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
      }
    }
    .padding(14)
    .vzGlassSolid()
  }

  private var ticker: String {
    var parts = ["\(stream.tokenIn)→\(stream.tokenOut) tok"]
    if stream.costUsd > 0 { parts.append(String(format: "$%.4f", stream.costUsd)) }
    if !stream.usageMeasured { parts[0] = "≈" + parts[0] }
    return parts.joined(separator: " · ")
  }
}

/// Starter prompts for the blank page.
struct TemplateSheet: View {
  var onPick: (PromptTemplate) -> Void

  var body: some View {
    NavigationStack {
      List(PromptTemplate.all) { template in
        Button { onPick(template) } label: {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(template.title).font(.vzBody(15, .medium)).foregroundStyle(VZ.text)
              Spacer()
              ChipLabel(text: template.mode.label, selected: false, icon: .mode(template.mode))
            }
            Text(template.hint).font(.vzBody(12)).foregroundStyle(VZ.muted)
          }
          .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Templates")
      .navigationBarTitleDisplayMode(.inline)
    }
    .vzSheet()
  }
}

/// The media privacy notice, acknowledged once per device.
struct MediaPrivacySheet: View {
  @Bindable var model: EnhanceViewModel
  @State private var keep = true

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Before you attach").font(.vzDisplay(26)).foregroundStyle(VZ.text)
      Text("Attached images are sent to the selected model to read what they contain. Kept attachments stay in your private storage (50 MB) until you remove them in Settings → Data & privacy. Choose \"Analyze without keeping\" and nothing is stored.")
        .font(.vzBody(14)).foregroundStyle(VZ.muted)
      Toggle("Keep attachments by default", isOn: $keep).font(.vzBody(15)).tint(VZ.accent)
      Button("Got it") { Task { await model.acknowledgePrivacyNotice(keepByDefault: keep) } }
        .buttonStyle(.laser)
      Button("Cancel") {
        model.pendingPick = []
        model.showPrivacyNotice = false
      }
      .buttonStyle(.quiet)
    }
    .padding(24)
    .vzSheet(detents: [.medium])
  }
}
