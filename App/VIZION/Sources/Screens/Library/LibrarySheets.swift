import SwiftUI
import VizionCore

// MARK: - Library sheets (filter · collection · draft editor) and the chip layout

/// Filter sheet: view · sort · model facets (only what's present) · tags · collections.
struct LibraryFilterSheet: View {
  @Bindable var model: LibraryViewModel
  @Environment(\.dismiss) private var dismiss
  @State private var draft = LibraryFilter.default

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          group("View") {
            VZSegmented(
              options: LibraryView.allCases.map { (id: $0, label: $0.label) },
              selection: Binding(
                get: { Optional(draft.view) },
                set: {
                  if let v = $0 {
                    draft.view = v
                    // Drafts always list by last edit (the query has no sort).
                    if v == .drafts {
                      draft.sort = .updated
                    }
                  }
                }
              ),
              accessibilityLabel: "View"
            )
          }
          if draft.view != .drafts {
            group("Sort") {
              VZSegmented(
                options: LibrarySort.allCases.map { (id: $0, label: $0.label) },
                selection: Binding(
                  get: { Optional(draft.sort) },
                  set: {
                    if let v = $0 {
                      draft.sort = v
                    }
                  }
                ),
                accessibilityLabel: "Sort"
              )
            }
          }
          if !model.facets.models.isEmpty {
            group("Model") {
              if let groups = LibraryFacets.groupModels(model.facets.models) {
                ForEach(groups, id: \.label) { g in
                  Text(g.label).vzCaps()
                  chips(g.models)
                }
              } else {
                chips(model.facets.models)
              }
            }
          }
          group("Mode") {
            chipRow(
              EnhanceMode.allCases.map { ($0.rawValue, $0.label) },
              selected: draft.mode?.rawValue
            ) { raw in
              draft.mode = draft.mode?.rawValue == raw ? nil : EnhanceMode(rawValue: raw)
            }
          }
          if !model.facets.tags.isEmpty {
            group("Tags") {
              chipRow(model.facets.tags.map { ($0, "#\($0)") }, selected: draft.tag) { raw in
                draft.tag = draft.tag == raw ? nil : raw
              }
            }
          }
          if !model.facets.collections.isEmpty {
            group("Collections") {
              chipRow(
                model.facets.collections.map { ($0.id, "\($0.name) (\($0.count))") },
                selected: draft.collection
              ) { raw in
                draft.collection = draft.collection == raw ? nil : raw
              }
            }
          }
        }
        .padding(20)
      }
      .navigationTitle("Filter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Reset") { draft = LibraryFilter(q: draft.q) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            model.filter = draft
            dismiss()
          }
        }
      }
    }
    .onAppear { draft = model.filter }
    .vzSheet(detents: [.large])
  }

  private func chips(_ models: [ModelFacet]) -> some View {
    chipRow(
      models.map { ($0.id, "\($0.label) (\($0.count))") },
      selected: draft.model?.rawValue
    ) { raw in
      draft.model = draft.model?.rawValue == raw ? nil : TargetModel.resolve(raw)
    }
  }

  private func chipRow(
    _ items: [(String, String)],
    selected: String?,
    onTap: @escaping (String) -> Void
  ) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(items, id: \.0) { id, label in
        Button { onTap(id) } label: { ChipLabel(text: label, selected: selected == id) }
          .buttonStyle(.pressable)
      }
    }
  }

  private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).vzCaps()
      content()
    }
  }
}

/// Move-to-collection sheet with create/rename/delete.
struct CollectionSheet: View {
  @Bindable var model: LibraryViewModel
  var card: PromptCard
  @Environment(\.dismiss) private var dismiss
  @State private var newName = ""

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button { Task { await model.move(card, to: nil); dismiss() } } label: {
            HStack {
              Text("No collection"); Spacer(); if card.collectionID == nil {
                IconView(
                  .check,
                  size: 16
                ).foregroundStyle(VZ.accent)
              }
            }
          }
          ForEach(model.facets.collections) { c in
            Button { Task { await model.move(card, to: c.id); dismiss() } } label: {
              HStack {
                Text(c.name); Text("\(c.count)").foregroundStyle(VZ.muted); Spacer(); if card
                  .collectionID == c.id {
                  IconView(
                    .check,
                    size: 16
                  ).foregroundStyle(VZ.accent)
                }
              }
            }
            .swipeActions {
              Button(role: .destructive) { Task { await model.deleteCollection(c.id) } } label: {
                Label(
                  "Delete",
                  systemImage: "trash"
                )
              }
            }
          }
        }
        .listRowBackground(VZ.surface)
        Section("New collection") {
          HStack {
            TextField("Name", text: $newName).vzInputFont()
            Button("Add") {
              Task {
                if let id = await model.createCollection(newName) {
                  await model.move(card, to: id)
                  dismiss()
                }
              }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
        .listRowBackground(VZ.surface)
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Move to collection")
      .navigationBarTitleDisplayMode(.inline)
    }
    .vzSheet()
  }
}

/// In-place draft editing (body only; resume is the route for target/mode).
struct DraftEditorSheet: View {
  @Bindable var model: LibraryViewModel
  var draft: DraftCard
  @Environment(\.dismiss) private var dismiss
  @State private var body_ = ""
  @State private var expectedUpdatedAt = ""
  @State private var loaded = false
  @State private var loadError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Edit draft").font(.vzDisplay(26)).foregroundStyle(VZ.text)
      if loaded {
        TextEditor(text: $body_).font(.vzBody(15)).scrollContentBackground(.hidden)
          .vzGlassSolid(cornerRadius: VZ.Radius.control)
        Button("Save") {
          Task {
            if await model.updateDraft(
              draft,
              body: body_,
              expectedUpdatedAt: expectedUpdatedAt
            ) {
              dismiss()
            }
          }
        }
        .buttonStyle(.laser)
      } else if let loadError {
        // Never an empty editor over a failed load: a save from it would only
        // fail later with a misleading conflict.
        VStack(alignment: .leading, spacing: 8) {
          Text("Couldn't open this draft. \(loadError)").font(.vzBody(13))
            .foregroundStyle(VZ.flare)
          Button("Retry") { Task { await load() } }.buttonStyle(.secondaryInline)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
      Button("Cancel") { dismiss() }.buttonStyle(.quiet)
    }
    .padding(20)
    .task { await load() }
    .vzSheet(detents: [.large])
  }

  private func load() async {
    loadError = nil
    do {
      let body = try await model.draftBody(draft)
      body_ = body.body
      expectedUpdatedAt = body.updatedAt
      loaded = true
    } catch {
      loadError = error.localizedDescription
    }
  }
}

/// Wrapping chip layout.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > width, x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
