import SwiftUI
import VizionCore

/// Saved-prompt browser: saved work leads; filters are summoned. One search
/// field + one Filter button (badge = active filters); two quick chips.
struct LibraryScreen: View {
  @Environment(AppEnvironment.self) private var env
  @State private var model: LibraryViewModel?
  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let model {
          LibraryBrowser(model: model, path: $path)
        } else {
          ProgressView()
        }
      }
      .navigationDestination(for: String.self) { id in PromptDetailScreen(promptID: id) }
      .toolbar(.hidden, for: .navigationBar)
    }
    .onAppear {
      if model == nil {
        let m = LibraryViewModel(env: env)
        model = m
        Task { await m.reload() }
      }
    }
    .onChange(of: env.pendingPromptID) { _, id in
      if let id {
        path.append(id)
        env.pendingPromptID = nil
      }
    }
  }
}

struct LibraryBrowser: View {
  @Bindable var model: LibraryViewModel
  @Binding var path: NavigationPath
  @Environment(AppEnvironment.self) private var env
  @State private var showFilters = false
  @State private var renaming: PromptCard?
  @State private var renameText = ""
  @State private var moving: PromptCard?
  @State private var editingDraft: DraftCard?

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ScreenHeader(title: "Library") {
          NewPromptButton(library: model)
        }
        ScreenColumn(spacing: 20) {
          toolbar
          if let error = model.error {
            errorCard(error)
          } else if model.filter.isDraftsView {
            draftsList
          } else {
            promptList
          }
          if !model.filter.isDraftsView { ActivityFeedView(events: model.activity) }
          VizionFooter()
        }
      }
    }
    .refreshable { await model.reload() }
    .sheet(isPresented: $showFilters) { LibraryFilterSheet(model: model) }
    .sheet(item: $moving) { card in CollectionSheet(model: model, card: card) }
    .sheet(item: $editingDraft) { draft in DraftEditorSheet(model: model, draft: draft) }
    .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField("Title", text: $renameText)
      Button("Save") {
        if let card = renaming { Task { await model.rename(card, to: renameText) } }
        renaming = nil
      }
      Button("Cancel", role: .cancel) { renaming = nil }
    }
  }

  // MARK: Toolbar

  private var toolbar: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        HStack(spacing: 8) {
          IconView(.search, size: 16).foregroundStyle(VZ.muted)
          TextField("Search titles", text: $model.searchDraft)
            .vzInputFont()
            .submitLabel(.search)
            .onSubmit { model.submitSearch() }
          if !model.searchDraft.isEmpty {
            Button {
              model.searchDraft = ""
              model.submitSearch()
            } label: { IconView(.close, size: 14) }
            .buttonStyle(.quiet).accessibilityLabel("Clear search")
          }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .vzGlass(cornerRadius: VZ.Radius.control)

        Button { showFilters = true } label: {
          HStack(spacing: 6) {
            IconView(.filter, size: 16)
            Text("Filter")
            if model.filter.activeCount > 0 {
              Text("\(model.filter.activeCount)")
                .font(.vzBody(11, .semibold)).foregroundStyle(VZ.onLaser)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(VZ.laser))
            }
          }
        }
        .buttonStyle(.secondaryInline)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          quickChip("All", view: .all)
          quickChip("Favorites", view: .favorites)
          quickChip("Drafts", view: .drafts)
          Button { model.filter = LibraryFilter(q: model.filter.q, view: model.filter.view, sort: .created) } label: {
            ChipLabel(text: "Recent", selected: model.filter.sort == .created)
          }
          .buttonStyle(.pressable)
        }
      }
    }
  }

  private func quickChip(_ label: String, view: LibraryView) -> some View {
    Button {
      model.filter = LibraryFilter(q: model.filter.q, model: model.filter.model, mode: model.filter.mode, view: view, sort: model.filter.sort)
    } label: {
      ChipLabel(text: label, selected: model.filter.view == view)
    }
    .buttonStyle(.pressable)
  }

  // MARK: Lists

  private var promptList: some View {
    VStack(spacing: 10) {
      if model.loading, model.cards.isEmpty {
        ProgressView().tint(VZ.accent).frame(maxWidth: .infinity).padding(24)
      } else if model.cards.isEmpty {
        emptyCard(
          model.filter.isDefault ? "Nothing saved yet" : "No matches",
          model.filter.isDefault ? "Enhance a prompt and save it — it lands here with every version." : "Try a broader filter."
        )
      } else {
        ForEach(model.cards) { card in
          NavigationLink(value: card.id) {
            PromptRow(card: card, collectionName: collectionName(card.collectionID))
          }
          .buttonStyle(.pressable)
          .contextMenu { contextMenu(card) }
        }
        if model.nextCursor != nil {
          Button(model.loadingMore ? "Loading…" : "Load more") { Task { await model.loadMore() } }
            .buttonStyle(.secondary).disabled(model.loadingMore)
        }
      }
    }
  }

  @ViewBuilder
  private func contextMenu(_ card: PromptCard) -> some View {
    if card.deleted {
      Button { Task { await model.restore(card) } } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
      Button(role: .destructive) { Task { await model.deleteForever(card) } } label: { Label("Delete forever", systemImage: "trash") }
    } else {
      Button {
        renameText = card.title
        renaming = card
      } label: { Label("Rename", systemImage: "pencil") }
      Button { Task { await model.toggleFavorite(card) } } label: {
        Label(card.favorite ? "Unfavorite" : "Favorite", systemImage: card.favorite ? "star.slash" : "star")
      }
      Button { moving = card } label: { Label("Move to collection", systemImage: "folder") }
      Button { Task { await model.setArchived(card, !card.archived) } } label: {
        Label(card.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
      }
      Button(role: .destructive) { Task { await model.softDelete(card) } } label: { Label("Delete", systemImage: "trash") }
      if card.archived {
        Button(role: .destructive) { Task { await model.deleteForever(card) } } label: { Label("Delete forever", systemImage: "trash.slash") }
      }
    }
  }

  private var draftsList: some View {
    VStack(spacing: 10) {
      if model.draftsUnavailable {
        emptyCard("Drafts aren't set up yet", "The drafts table is missing on the server — apply the drafts migration.")
      } else if model.drafts.isEmpty, !model.loading {
        emptyCard("No drafts", "Save a composer draft from the New prompt button to come back to it later.")
      } else {
        ForEach(model.drafts) { draft in
          DraftRowView(draft: draft) {
            Task {
              if await model.resume(draft) {
                env.toasts.show("Draft moved into the composer")
                env.pendingDraft = nil
              }
            }
          } onEdit: {
            editingDraft = draft
          } onDelete: {
            Task { await model.deleteDraft(draft) }
          }
        }
        if model.nextCursor != nil {
          Button(model.loadingMore ? "Loading…" : "Load more") { Task { await model.loadMore() } }
            .buttonStyle(.secondary).disabled(model.loadingMore)
        }
      }
    }
  }

  private func collectionName(_ id: String?) -> String? {
    guard let id else { return nil }
    return model.facets.collections.first { $0.id == id }?.name
  }

  private func emptyCard(_ title: String, _ body: String) -> some View {
    VStack(spacing: 6) {
      Text(title).font(.vzDisplay(22)).foregroundStyle(VZ.text)
      Text(body).font(.vzBody(13)).foregroundStyle(VZ.muted).multilineTextAlignment(.center)
    }
    .padding(24).frame(maxWidth: .infinity).vzGlass()
  }

  private func errorCard(_ text: String) -> some View {
    VStack(spacing: 8) {
      Text("Couldn't load your library").font(.vzDisplay(22)).foregroundStyle(VZ.text)
      Text(text).font(.vzBody(13)).foregroundStyle(VZ.muted).multilineTextAlignment(.center)
      Button("Retry") { Task { await model.reload() } }.buttonStyle(.secondaryInline)
    }
    .padding(24).frame(maxWidth: .infinity).vzGlass()
  }
}

struct PromptRow: View {
  var card: PromptCard
  var collectionName: String?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          if card.favorite { IconView(.star, size: 12, filled: true).foregroundStyle(VZ.accent) }
          Text(card.title).font(.vzBody(15, .medium)).foregroundStyle(VZ.text).lineLimit(2)
        }
        if let preview = card.preview, !preview.isEmpty {
          Text(preview).font(.vzBody(12)).foregroundStyle(VZ.muted).lineLimit(2)
        }
        HStack(spacing: 8) {
          HStack(spacing: 4) {
            TargetMark(targetID: card.targetModel, size: 12)
            Text(card.modelLabel)
          }
          .foregroundStyle(card.developer.map(VZ.developer) ?? VZ.muted)
          if let mode = card.modeLabel { Text(mode) }
          if card.versions > 1 { Text("v\(card.versions)") }
          if let collectionName { HStack(spacing: 3) { IconView(.folder, size: 11); Text(collectionName) } }
          ForEach(card.tags.prefix(3), id: \.self) { Text("#\($0)") }
          Spacer()
          Text(LibraryUtil.relativeTime(iso: card.updatedAt))
        }
        .font(.vzBody(11)).foregroundStyle(VZ.muted).lineLimit(1)
      }
      IconView(.chevronRight, size: 14).foregroundStyle(VZ.muted)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .vzGlass()
    .overlay(alignment: .topTrailing) {
      // Trailing corner developer-accent field (web: dev-accents.css).
      if let developer = card.developer {
        RadialGradient(colors: [VZ.developer(developer).opacity(0.26), .clear], center: .topTrailing, startRadius: 0, endRadius: 140)
          .clipShape(RoundedRectangle(cornerRadius: VZ.Radius.panel, style: .continuous))
          .allowsHitTesting(false)
      }
    }
  }
}

struct DraftRowView: View {
  var draft: DraftCard
  var onResume: () -> Void
  var onEdit: () -> Void
  var onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(draft.title).font(.vzBody(15, .medium)).foregroundStyle(VZ.text).lineLimit(2)
      Text(draft.preview).font(.vzBody(12)).foregroundStyle(VZ.muted).lineLimit(3)
      HStack(spacing: 8) {
        Text(draft.modelLabel)
        Text(draft.modeLabel)
        if let level = draft.thinkingLevel { Text(ThinkingLevel(rawValue: level)?.label ?? level) }
        Spacer()
        Text(LibraryUtil.relativeTime(iso: draft.updatedAt))
      }
      .font(.vzBody(11)).foregroundStyle(VZ.muted)
      HStack(spacing: 8) {
        Button("Resume", action: onResume).buttonStyle(.laserInline)
        Button("Edit", action: onEdit).buttonStyle(.secondaryInline)
        Button("Delete", action: onDelete).buttonStyle(.destructive)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .vzGlass()
  }
}

struct ActivityFeedView: View {
  var events: [ActivityEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionCaption(text: "Activity", icon: .history)
      if events.isEmpty {
        Text("Your activity feed will stream created, enhanced, saved, shared, and restored events.")
          .font(.vzBody(13)).foregroundStyle(VZ.muted).padding(16).frame(maxWidth: .infinity).vzGlass()
      } else {
        VStack(spacing: 0) {
          ForEach(events) { event in
            let row = HStack {
              (Text(event.verb).foregroundStyle(VZ.text)
                + Text(event.showsTitle ? " “\(event.title ?? "")”" : "").foregroundStyle(VZ.muted))
                .font(.vzBody(13))
                .lineLimit(1)
              Spacer()
              Text(LibraryUtil.relativeTime(iso: event.createdAt)).font(.vzBody(11)).foregroundStyle(VZ.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if let promptID = event.promptID {
              NavigationLink(value: promptID) { row }.buttonStyle(.plain)
            } else {
              row
            }
            Rectangle().fill(VZ.hair).frame(height: 1)
          }
        }
        .vzGlass()
      }
    }
  }
}

/// "New prompt" (web: `NewPromptFab`): back to an empty composer, asking to
/// save or discard a draft in progress rather than wiping it.
struct NewPromptButton: View {
  var library: LibraryViewModel
  @Environment(AppEnvironment.self) private var env
  @State private var ask = false

  var body: some View {
    Button {
      if env.ui.editorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        env.pendingDraft = ""
      } else {
        ask = true
      }
    } label: {
      IconView(.plus, size: 22).foregroundStyle(VZ.onLaser)
        .frame(width: 40, height: 40)
        .background(Circle().fill(VZ.laser))
        .shadow(color: VZ.laserGlow, radius: 10, y: 3)
    }
    .buttonStyle(.pressable)
    .accessibilityLabel("New prompt")
    .confirmationDialog("Save this draft?", isPresented: $ask, titleVisibility: .visible) {
      Button("Save draft") {
        Task {
          if await library.saveComposerDraft() {
            env.ui.editorDraft = ""
            env.toasts.show("Draft saved to your library")
            env.pendingDraft = ""
          }
        }
      }
      Button("Discard", role: .destructive) {
        let discarded = env.ui.editorDraft
        env.ui.editorDraft = ""
        env.toasts.show("Draft discarded", actionLabel: "Undo") { env.ui.editorDraft = discarded }
        env.pendingDraft = ""
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your composer has a prompt in progress. Save it to your library to come back to it, or discard it and start fresh.")
    }
  }
}

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
              selection: Binding(get: { Optional(draft.view) }, set: { if let v = $0 { draft.view = v } }),
              accessibilityLabel: "View")
          }
          group("Sort") {
            VZSegmented(
              options: LibrarySort.allCases.map { (id: $0, label: $0.label) },
              selection: Binding(get: { Optional(draft.sort) }, set: { if let v = $0 { draft.sort = v } }),
              accessibilityLabel: "Sort")
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
            chipRow(EnhanceMode.allCases.map { ($0.rawValue, $0.label) }, selected: draft.mode?.rawValue) { raw in
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
              chipRow(model.facets.collections.map { ($0.id, "\($0.name) (\($0.count))") }, selected: draft.collection) { raw in
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
        ToolbarItem(placement: .cancellationAction) { Button("Reset") { draft = LibraryFilter(q: draft.q) } }
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
    chipRow(models.map { ($0.id, "\($0.label) (\($0.count))") }, selected: draft.model?.rawValue) { raw in
      draft.model = draft.model?.rawValue == raw ? nil : TargetModel.resolve(raw)
    }
  }

  private func chipRow(_ items: [(String, String)], selected: String?, onTap: @escaping (String) -> Void) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(items, id: \.0) { id, label in
        Button { onTap(id) } label: { ChipLabel(text: label, selected: selected == id) }.buttonStyle(.pressable)
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
            HStack { Text("No collection"); Spacer(); if card.collectionID == nil { IconView(.check, size: 16).foregroundStyle(VZ.accent) } }
          }
          ForEach(model.facets.collections) { c in
            Button { Task { await model.move(card, to: c.id); dismiss() } } label: {
              HStack { Text(c.name); Text("\(c.count)").foregroundStyle(VZ.muted); Spacer(); if card.collectionID == c.id { IconView(.check, size: 16).foregroundStyle(VZ.accent) } }
            }
            .swipeActions { Button(role: .destructive) { Task { await model.deleteCollection(c.id) } } label: { Label("Delete", systemImage: "trash") } }
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Edit draft").font(.vzDisplay(26)).foregroundStyle(VZ.text)
      if loaded {
        TextEditor(text: $body_).font(.vzBody(15)).scrollContentBackground(.hidden).vzGlassSolid(cornerRadius: VZ.Radius.control)
        Button("Save") {
          Task { if await model.updateDraft(draft, body: body_, expectedUpdatedAt: expectedUpdatedAt) { dismiss() } }
        }
        .buttonStyle(.laser)
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
      Button("Cancel") { dismiss() }.buttonStyle(.quiet)
    }
    .padding(20)
    .task {
      if let body = await model.draftBody(draft) {
        body_ = body.body
        expectedUpdatedAt = body.updatedAt
      }
      loaded = true
    }
    .vzSheet(detents: [.large])
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

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
