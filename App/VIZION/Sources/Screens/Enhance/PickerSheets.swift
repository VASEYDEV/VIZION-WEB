import SwiftUI
import VizionCore

/// Model target picker — grouped by developer with the marks, an Auto row on
/// top (routing in the composer; "no stored default" in Settings), and the
/// budget dial under Auto when routing is offered.
struct TargetPickerSheet: View {
  @Binding var selection: TargetModel
  /// Pass both to offer the Auto row.
  var auto: Binding<Bool>?
  var autoPreference: Binding<AutoPreference>?
  var autoDescription = "Picks the model per run."
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let auto {
          Section {
            Button {
              auto.wrappedValue = true
            } label: {
              row(label: "Auto", detail: autoDescription, selected: auto.wrappedValue) {
                IconView(.sparkle, size: 18).foregroundStyle(VZ.accent)
              }
            }
            if auto.wrappedValue, let autoPreference {
              VStack(alignment: .leading, spacing: 6) {
                Text("Budget").vzCaps()
                VZSegmented(
                  options: AutoPreference.detents
                    .compactMap { d in AutoPreference(rawValue: d.id).map { (
                      id: $0,
                      label: d.label
                    ) } },
                  selection: Binding(
                    get: { Optional(autoPreference.wrappedValue) },
                    set: {
                      if let v = $0 {
                        autoPreference.wrappedValue = v
                      }
                    }
                  ),
                  fill: true, accessibilityLabel: "Routing preference"
                )
                if autoPreference.wrappedValue == .quality {
                  Text(AutoPreference.peakCaption).font(.vzBody(11)).foregroundStyle(VZ.muted)
                }
              }
              .listRowBackground(Color.clear)
            }
          }
          .listRowBackground(VZ.surface)
        }
        ForEach(TargetModel.grouped, id: \.developer) { group in
          Section(group.developer.label) {
            ForEach(group.models) { model in
              Button {
                selection = model
                auto?.wrappedValue = false
                dismiss()
              } label: {
                row(
                  label: model.label,
                  detail: model.hasThinkingDial ? "Thinking dial" : nil,
                  selected: !(auto?.wrappedValue ?? false) && selection == model
                ) {
                  DeveloperIcon(developer: group.developer, size: 18).foregroundStyle(VZ.accent)
                }
              }
            }
          }
          .listRowBackground(VZ.surface)
        }
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Target model")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .vzSheet(detents: [.large])
  }

  private func row(
    label: String,
    detail: String?,
    selected: Bool,
    @ViewBuilder mark: () -> some View
  ) -> some View {
    HStack(spacing: 12) {
      mark().frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.vzBody(15, .medium)).foregroundStyle(VZ.text)
        if let detail {
          Text(detail).font(.vzBody(12)).foregroundStyle(VZ.muted)
        }
      }
      Spacer()
      if selected {
        IconView(.check, size: 18).foregroundStyle(VZ.accent)
      }
    }
    .contentShape(Rectangle())
  }
}

/// Reasoning-depth dial — the ladder is [Auto, …the target's own levels], so
/// the stop count adapts per model (4/5/6). A segmented ladder here; the
/// web's press-and-hold capsule is a later refinement (parity ledger).
struct ThinkingDialSheet: View {
  var target: TargetModel
  @Binding var level: ThinkingLevel?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Thinking depth").font(.vzDisplay(26)).foregroundStyle(VZ.text)
      Text(
        """
        How hard \(target.label) reasons before it answers. \
        Auto sends nothing — the provider's own default applies.
        """
      )
      .font(.vzBody(13)).foregroundStyle(VZ.muted)
      let detents = ThinkingDial.detents(for: target.thinkingLadder)
      VZSegmented(
        options: detents.map { (id: $0.id, label: $0.label) },
        selection: Binding(
          get: { level?.rawValue ?? "auto" },
          set: { level = $0.flatMap { ThinkingLevel(rawValue: $0) } }
        ),
        fill: true, accessibilityLabel: "Thinking depth"
      )
      if let level, level == target.thinkingLadder.last {
        Text(ThinkingDial.peakCaption).font(.vzBody(11)).foregroundStyle(VZ.ultra)
      }
      Button("Done") { dismiss() }.buttonStyle(.laser)
    }
    .padding(24)
    .vzSheet(detents: [.medium])
  }
}

/// Sign-in provider marks (web: `ProviderIcon`): the official four-colour
/// Google "G" (brand guidelines require the multicolour glyph, never
/// recoloured) and the monochrome GitHub mark on the theme's text ink.
struct ProviderMark: View {
  var provider: SupabaseService.OAuthProvider
  var size: CGFloat = 18

  var body: some View {
    switch provider {
    case .google:
      ZStack {
        ForEach(Array(ProviderPaths.google.enumerated()), id: \.offset) { _, piece in
          SVGShape(commands: piece.commands, viewBox: CGSize(width: 24, height: 24))
            .fill(piece.color)
        }
      }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
    case .github:
      SVGShape(commands: ProviderPaths.github, viewBox: CGSize(width: 24, height: 24))
        .fill(VZ.text, style: FillStyle(eoFill: true))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
  }
}

enum ProviderPaths {
  struct Piece {
    let color: Color
    let commands: [SVGPathCommand]
  }

  // swiftlint:disable line_length
  static let google: [Piece] = [
    (
      0x4285F4,
      "M23.52 12.27c0-.82-.07-1.6-.21-2.36H12v4.47h6.46a5.52 5.52 0 0 1-2.4 3.62v3h3.88c2.27-2.09 3.58-5.17 3.58-8.73Z"
    ),
    (
      0x34A853,
      "M12 24c3.24 0 5.96-1.08 7.94-2.92l-3.88-3c-1.08.72-2.45 1.15-4.06 1.15-3.12 0-5.77-2.11-6.71-4.95H1.29v3.1A12 12 0 0 0 12 24Z"
    ),
    (0xFBBC05, "M5.29 14.28a7.21 7.21 0 0 1 0-4.56v-3.1H1.29a12 12 0 0 0 0 10.76l4-3.1Z"),
    (
      0xEA4335,
      "M12 4.75c1.76 0 3.34.61 4.59 1.8l3.43-3.43C17.95 1.19 15.24 0 12 0A12 12 0 0 0 1.29 6.62l4 3.1C6.23 6.86 8.88 4.75 12 4.75Z"
    ),
  ].map { Piece(color: Color(hex: $0.0), commands: (try? SVGPathParser.parse($0.1)) ?? []) }

  static let github: [SVGPathCommand] = (try? SVGPathParser.parse(
    "M12 .5A11.5 11.5 0 0 0 .5 12a11.5 11.5 0 0 0 7.86 10.92c.57.1.78-.25.78-.55v-2.16c-3.2.7-3.87-1.36-3.87-1.36-.53-1.34-1.28-1.7-1.28-1.7-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.2 1.77 1.2 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.26.73-1.55-2.56-.3-5.25-1.28-5.25-5.7 0-1.26.45-2.28 1.19-3.09-.12-.3-.52-1.47.11-3.06 0 0 .97-.31 3.18 1.18a11 11 0 0 1 5.8 0c2.2-1.5 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.06.74.81 1.19 1.83 1.19 3.09 0 4.43-2.7 5.4-5.27 5.69.41.36.78 1.06.78 2.14v3.17c0 .31.21.66.79.55A11.5 11.5 0 0 0 23.5 12 11.5 11.5 0 0 0 12 .5Z"
  )) ?? []
  // swiftlint:enable line_length
}
