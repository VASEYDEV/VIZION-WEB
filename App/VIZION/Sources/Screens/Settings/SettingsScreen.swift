import PhotosUI
import SwiftUI
import VizionCore

/// Settings: Identity · Account · Defaults · Appearance · Data & privacy ·
/// [Owner] · About. One persistence path per control with status beside it,
/// optimistic apply + rollback on failure.
struct SettingsScreen: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ScreenHeader(title: "Settings")
        ScreenColumn(spacing: 20) {
          if let profile = env.profile {
            IdentitySection(profile: profile)
            AccountSection(profile: profile)
            DefaultsSection(profile: profile)
            AppearanceSection(profile: profile)
            DataPrivacySection()
            if env.isOwner {
              OwnerSection()
            }
            AboutSection()
          } else {
            Text("We couldn't load your settings. Pull to refresh.")
              .font(.vzBody(13)).foregroundStyle(VZ.muted).padding(20).frame(maxWidth: .infinity)
              .vzGlass()
          }
          VizionFooter()
        }
      }
    }
    .refreshable { await env.refreshAccount() }
    .scrollDismissesKeyboard(.interactively)
  }
}

struct SettingsSection<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(.vzDisplay(20, relativeTo: .title3)).tracking(0.6).foregroundStyle(VZ.text)
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .vzGlass()
  }
}

struct SettingsRow<Trailing: View>: View {
  var label: String
  var detail: String?
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.vzBody(15)).foregroundStyle(VZ.text)
        if let detail {
          Text(detail).font(.vzBody(12)).foregroundStyle(VZ.muted)
        }
      }
      Spacer(minLength: 8)
      trailing
    }
  }
}

struct FieldStatus: View {
  enum Status: Equatable { case idle, saving, saved, failed(String) }
  var status: Status

  var body: some View {
    switch status {
    case .idle: EmptyView()
    case .saving: Text("Saving…").font(.vzBody(12)).foregroundStyle(VZ.muted)
    case .saved: Text("Saved ✓").font(.vzBody(12)).foregroundStyle(VZ.pulseInk)
    case let .failed(message): Text(message).font(.vzBody(12)).foregroundStyle(VZ.flare)
    }
  }
}

/// Optimistic write helper: apply, round-trip, roll back on failure. Writes
/// from one call site run in order and only the latest may report or roll
/// back, so two quick selections can neither land on the server out of order
/// nor revert a newer choice when the older request fails last.
@MainActor
func settingWrite(
  _ status: Binding<FieldStatus.Status>,
  site: String = "\(#fileID):\(#line)",
  rollback: @escaping () -> Void = {},
  work: @escaping () async throws -> Void
) {
  let generation = SettingWrites.next(site)
  let previous = SettingWrites.chains[site]
  SettingWrites.chains[site] = Task {
    await previous?.value
    status.wrappedValue = .saving
    do {
      try await work()
      guard SettingWrites.generations[site] == generation else { return }
      status.wrappedValue = .saved
      try? await Task.sleep(for: .seconds(2))
      if status.wrappedValue == .saved, SettingWrites.generations[site] == generation {
        status.wrappedValue = .idle
      }
    } catch {
      guard SettingWrites.generations[site] == generation else { return }
      rollback()
      status.wrappedValue = .failed(error.localizedDescription)
    }
  }
}

/// Per-call-site bookkeeping for `settingWrite`.
@MainActor
private enum SettingWrites {
  static var chains: [String: Task<Void, Never>] = [:]
  static var generations: [String: Int] = [:]

  static func next(_ site: String) -> Int {
    let n = (generations[site] ?? 0) + 1
    generations[site] = n
    return n
  }
}

// MARK: - Identity

struct IdentitySection: View {
  var profile: Profile
  @Environment(AppEnvironment.self) private var env
  @State private var fullName = ""
  @State private var displayName = ""
  @State private var status: FieldStatus.Status = .idle
  @State private var avatarStatus: FieldStatus.Status = .idle
  @State private var avatarPick: PhotosPickerItem?

  private var dirty: Bool {
    fullName != (profile.full_name ?? "") || displayName != (profile.display_name ?? "")
  }

  private var displayNameValid: Bool {
    displayName.trimmingCharacters(in: .whitespaces).isEmpty || LibraryUtil
      .isValidDisplayName(displayName)
  }

  var body: some View {
    SettingsSection(title: "Identity") {
      HStack(spacing: 14) {
        AsyncImage(url: profile.avatar_url.flatMap(URL.init(string:))) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          ZStack {
            Circle().fill(VZ.surface)
            Text(String((profile.display_name ?? profile.email ?? "?").prefix(1)).uppercased())
              .font(.vzDisplay(24)).foregroundStyle(VZ.accent)
          }
        }
        .frame(width: 64, height: 64).clipShape(Circle())
        .overlay(Circle().strokeBorder(VZ.hair, lineWidth: 1))
        VStack(alignment: .leading, spacing: 4) {
          PhotosPicker(selection: $avatarPick, matching: .images) { Text("Change avatar") }
            .buttonStyle(.secondaryInline)
          FieldStatus(status: avatarStatus)
        }
      }
      .onChange(of: avatarPick) { _, item in
        guard let item else { return }
        settingWrite($avatarStatus) {
          guard let data = try await item.loadTransferable(type: Data.self),
                let png = ImageProcessing.avatarPNG(data) else {
            throw ProfileRepository.Failure.message("Couldn't read that image.")
          }
          _ = try await env.profiles?.uploadAvatar(png: png)
          await env.refreshAccount()
          avatarPick = nil
        }
      }
      TextField("Full name", text: $fullName).textContentType(.name).vzInputFont().vzField()
      VStack(alignment: .leading, spacing: 4) {
        TextField("Display name", text: $displayName).textInputAutocapitalization(.never)
          .autocorrectionDisabled().vzInputFont().vzField()
        Text(LibraryUtil.displayNameRule).font(.vzBody(11))
          .foregroundStyle(!displayNameValid ? VZ.flare : VZ.muted)
      }
      HStack {
        Button("Save") {
          settingWrite(
            $status,
            rollback: {
              fullName = profile.full_name ?? ""
              displayName = profile.display_name ?? ""
            },
            work: {
              try await env.profiles?.update(ProfileRepository.ProfilePatch(
                fullName: .some(fullName),
                displayName: .some(displayName)
              ))
              await env.refreshAccount()
            }
          )
        }
        .buttonStyle(.laserInline).disabled(!dirty || !displayNameValid)
        FieldStatus(status: status)
      }
    }
    .onAppear {
      fullName = profile.full_name ?? ""
      displayName = profile.display_name ?? ""
    }
  }
}

// MARK: - Account

struct AccountSection: View {
  var profile: Profile
  @Environment(AppEnvironment.self) private var env
  @State private var showEmail = false
  @State private var newEmail = ""
  @State private var emailStatus: FieldStatus.Status = .idle
  @State private var showPassword = false
  @State private var password = ""
  @State private var confirm = ""
  @State private var passwordStatus: FieldStatus.Status = .idle
  @State private var confirmSignOut = false

  var body: some View {
    SettingsSection(title: "Account") {
      SettingsRow(label: "Email", detail: env.session?.email ?? profile.email ?? "") {
        Button("Change") { showEmail = true }.buttonStyle(.secondaryInline)
      }
      if let pending = env.session?.newEmail {
        Text("Confirm the link we sent to \(pending) to finish changing your email.")
          .font(.vzBody(12)).foregroundStyle(VZ.amberInk)
      }
      FieldStatus(status: emailStatus)
      Rectangle().fill(VZ.hair).frame(height: 1)
      SettingsRow(label: "Connection", detail: profile.auth_method?.connectionLabel ?? "—") {
        if let method = profile.auth_method, method != .magicLink {
          ProviderMark(provider: method == .github ? .github : .google, size: 18)
        }
      }
      Rectangle().fill(VZ.hair).frame(height: 1)
      SettingsRow(
        label: "Password",
        detail: profile.password_set == true ? "Set" : "Not set — magic link only"
      ) {
        Button(profile.password_set == true ? "Change" : "Set") { showPassword = true }
          .buttonStyle(.secondaryInline)
      }
      FieldStatus(status: passwordStatus)
      Rectangle().fill(VZ.hair).frame(height: 1)
      Button("Sign out") { confirmSignOut = true }.buttonStyle(.secondary)
    }
    .confirmationDialog(
      "Sign out of VIZION?",
      isPresented: $confirmSignOut,
      titleVisibility: .visible
    ) {
      Button("Sign out", role: .destructive) { Task { await env.signOut() } }
    }
    .sheet(isPresented: $showEmail) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Change email").font(.vzDisplay(26)).foregroundStyle(VZ.text)
        Text("We'll send a confirmation to the new address; the change applies once you open it.")
          .font(.vzBody(13)).foregroundStyle(VZ.muted)
        TextField("New email", text: $newEmail).keyboardType(.emailAddress)
          .textInputAutocapitalization(.never).autocorrectionDisabled().vzInputFont().vzField()
        Button("Send confirmation") {
          let value = newEmail.trimmingCharacters(in: .whitespaces)
          showEmail = false
          settingWrite($emailStatus) {
            try await env.supabase?.updateEmail(value)
            newEmail = ""
            await env.refreshAccount()
          }
        }
        .buttonStyle(.laser).disabled(newEmail.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Cancel") { showEmail = false }.buttonStyle(.quiet)
      }
      .padding(24).vzSheet(detents: [.medium])
    }
    .sheet(isPresented: $showPassword) {
      VStack(alignment: .leading, spacing: 12) {
        Text(profile.password_set == true ? "Change password" : "Set a password")
          .font(.vzDisplay(26)).foregroundStyle(VZ.text)
        SecureField("New password", text: $password).textContentType(.newPassword).vzInputFont()
          .vzField()
        SecureField("Confirm password", text: $confirm).textContentType(.newPassword).vzInputFont()
          .vzField()
        Text(PasswordRule.text).font(.vzBody(11)).foregroundStyle(VZ.muted)
        Button("Save password") {
          if let weak = PasswordRule.validate(password) {
            passwordStatus = .failed(weak)
            showPassword = false
            return
          }
          guard password == confirm else {
            passwordStatus = .failed("Passwords don't match.")
            showPassword = false
            return
          }
          showPassword = false
          settingWrite($passwordStatus) {
            try await env.supabase?.updatePassword(password)
            try await env.profiles?.setPasswordSet()
            password = ""
            confirm = ""
            await env.refreshAccount()
          }
        }
        .buttonStyle(.laser)
        Button("Cancel") { showPassword = false }.buttonStyle(.quiet)
      }
      .padding(24).vzSheet(detents: [.medium, .large])
    }
  }
}

// MARK: - Defaults

struct DefaultsSection: View {
  var profile: Profile
  @Environment(AppEnvironment.self) private var env
  @State private var showPicker = false
  @State private var status: FieldStatus.Status = .idle
  @State private var picked: TargetModel = .default
  @State private var isAuto = true

  var body: some View {
    SettingsSection(title: "Defaults") {
      SettingsRow(
        label: "Default model",
        detail: isAuto ? "No default — each session starts on Auto" : picked.label
      ) {
        Button { showPicker = true } label: {
          HStack(spacing: 6) {
            if isAuto {
              IconView(.sparkle, size: 14)
            } else {
              DeveloperIcon(
                developer: picked.developer,
                size: 14
              )
            }
            Text(isAuto ? "Auto" : picked.label)
            IconView(.chevronDown, size: 12)
          }
        }
        .buttonStyle(.secondaryInline)
      }
      FieldStatus(status: status)
    }
    .onAppear {
      picked = profile.defaultTarget ?? env.ui.targetModel
      isAuto = profile.defaultTarget == nil
    }
    .sheet(isPresented: $showPicker, onDismiss: commit) {
      TargetPickerSheet(
        selection: $picked,
        auto: $isAuto,
        autoDescription: "No default — each session starts on Auto."
      )
    }
  }

  /// `nil` = cleared → the account starts on Auto. The live store is written
  /// through so the composer reflects the choice immediately.
  private func commit() {
    let next: TargetModel? = isAuto ? nil : picked
    guard next != profile.defaultTarget else { return }
    let ui = env.ui
    let prevAuto = ui.autoTarget
    let prevTarget = ui.targetModel
    if let next {
      ui.targetModel = next
      ui.autoTarget = false
    } else {
      ui.autoTarget = true
    }
    settingWrite(
      $status,
      rollback: {
        ui.autoTarget = prevAuto
        ui.targetModel = prevTarget
        picked = profile.defaultTarget ?? prevTarget
        isAuto = profile.defaultTarget == nil
      },
      work: {
        try await env.profiles?.update(ProfileRepository.ProfilePatch(defaultModel: .some(next)))
        await env.refreshAccount()
      }
    )
  }
}

// MARK: - Appearance

struct AppearanceSection: View {
  var profile: Profile
  @Environment(AppEnvironment.self) private var env
  @State private var status: FieldStatus.Status = .idle

  var body: some View {
    @Bindable var ui = env.ui
    SettingsSection(title: "Appearance") {
      SettingsRow(label: "Theme", detail: nil) {
        VZSegmented(
          options: AppTheme.allCases.map { (id: $0, label: $0.label) },
          selection: Binding(
            get: { Optional(ui.theme) },
            set: {
              if let theme = $0 {
                setTheme(theme)
              }
            }
          ),
          accessibilityLabel: "Theme"
        )
      }
      FieldStatus(status: status)
      Rectangle().fill(VZ.hair).frame(height: 1)
      SettingsRow(
        label: "Reduced effects",
        detail: "Turns off the ambient blooms on this device."
      ) {
        Toggle("", isOn: $ui.reducedEffects).labelsHidden().tint(VZ.accent)
      }
    }
  }

  private func setTheme(_ theme: AppTheme) {
    let prev = env.ui.theme
    env.ui.theme = theme
    settingWrite(
      $status,
      rollback: { env.ui.theme = prev },
      work: { try await env.profiles?.update(ProfileRepository.ProfilePatch(theme: theme)) }
    )
  }
}

// MARK: - Data & privacy

struct DataPrivacySection: View {
  @Environment(AppEnvironment.self) private var env
  @State private var media: [MediaAssetRow] = []
  /// A failed refresh keeps the last-known rows; an empty list would read as
  /// "0 B stored" and hide every removal control.
  @State private var mediaError: String?
  @State private var exportURL: URL?
  @State private var exportStatus: FieldStatus.Status = .idle
  @State private var confirmDelete = false
  @State private var deleteText = ""
  @State private var deleteStatus: FieldStatus.Status = .idle

  private var usedBytes: Int {
    media.reduce(0) { $0 + $1.size_bytes }
  }

  var body: some View {
    SettingsSection(title: "Data & privacy") {
      SettingsRow(
        label: "Draft on this device",
        detail: "The composer draft is cached locally for convenience."
      ) {
        Button("Clear draft") {
          let prior = env.ui.editorDraft
          env.ui.editorDraft = ""
          env.toasts
            .show("Draft cleared on this device", actionLabel: "Undo") { env.ui.editorDraft = prior
            }
        }
        .buttonStyle(.secondaryInline)
        .disabled(env.ui.editorDraft.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      Rectangle().fill(VZ.hair).frame(height: 1)
      VStack(alignment: .leading, spacing: 8) {
        let budget = MediaBudget.status(usedBytes: usedBytes)
        SettingsRow(
          label: "Stored media",
          detail: "\(MediaBudget.formatBytes(usedBytes)) of \(MediaBudget.formatBytes(budget.quotaBytes))"
        ) {
          Button { Task { await loadMedia() } } label: { IconView(.refresh, size: 16) }
            .buttonStyle(.quiet)
        }
        ProgressView(value: min(budget.fraction, 1)).tint(budget.warn ? VZ.amber : VZ.accent)
        if let mediaError {
          HStack(spacing: 8) {
            Text("Couldn't refresh stored media. \(mediaError)").font(.vzBody(12))
              .foregroundStyle(VZ.flare)
            Button("Retry") { Task { await loadMedia() } }.buttonStyle(.secondaryInline)
          }
        }
        ForEach(media) { asset in
          HStack(spacing: 8) {
            Text(asset.original_name ?? asset.storage_path).font(.vzBody(12))
              .foregroundStyle(VZ.text).lineLimit(1)
            Text(MediaBudget.formatBytes(asset.size_bytes)).font(.vzBody(11))
              .foregroundStyle(VZ.muted)
            if asset
              .status !=
              "ready" {
              Text(asset.status).font(.vzBody(11)).foregroundStyle(VZ.amberInk)
            }
            Spacer()
            Button { Task { await delete(asset) } } label: { IconView(.trash, size: 14) }
              .buttonStyle(.quiet).accessibilityLabel("Remove")
          }
        }
      }
      Text(
        """
        Prompts and their versions stay until you delete them. Attached media stays in your \
        private storage (50 MB) until you remove it here or in the composer tray — or attach \
        with "Analyze without keeping" and nothing is stored. Usage records are kept for \
        cost-cap accounting.
        """
      )
      .font(.vzBody(11)).foregroundStyle(VZ.muted)
      Rectangle().fill(VZ.hair).frame(height: 1)
      SettingsRow(
        label: "Export my data",
        detail: "Profile, prompts, versions, and media metadata as JSON."
      ) {
        if let exportURL {
          ShareLink(item: exportURL) { Text("Share") }.buttonStyle(.secondaryInline)
        } else {
          Button("Export") {
            settingWrite($exportStatus) {
              guard let data = try await env.profiles?.exportJSON() else { return }
              let url = FileManager.default.temporaryDirectory.appending(path: "vizion-export.json")
              try data.write(to: url, options: .atomic)
              exportURL = url
            }
          }
          .buttonStyle(.secondaryInline)
        }
      }
      FieldStatus(status: exportStatus)
      Rectangle().fill(VZ.hair).frame(height: 1)
      SettingsRow(
        label: "Delete account",
        detail: """
        Permanently deletes your sign-in, profile, prompts and all their versions, and stored \
        media. This cannot be undone.
        """
      ) {
        Button("Delete…") { confirmDelete = true }.buttonStyle(.destructive)
      }
      FieldStatus(status: deleteStatus)
    }
    .task { await loadMedia() }
    .alert("Delete your account?", isPresented: $confirmDelete) {
      TextField("Type DELETE to confirm", text: $deleteText)
      Button("Delete forever", role: .destructive) {
        guard deleteText == "DELETE" else { return }
        settingWrite($deleteStatus) {
          try await env.api?.deleteAccount()
          await env.signOut()
        }
      }
      Button("Cancel", role: .cancel) { deleteText = "" }
    } message: {
      Text("Type DELETE to confirm. Everything is removed immediately.")
    }
  }

  private func loadMedia() async {
    do {
      media = try await env.profiles?.mediaAssets() ?? []
      mediaError = nil
    } catch {
      mediaError = error.localizedDescription
    }
  }

  private func delete(_ asset: MediaAssetRow) async {
    do {
      try await env.profiles?.deleteMediaAsset(asset)
      await loadMedia()
      env.toasts.show("Removed")
    } catch {
      env.toasts.error(error.localizedDescription)
    }
  }
}

// MARK: - Owner

struct OwnerSection: View {
  @Environment(AppEnvironment.self) private var env
  @State private var openAccess = true
  @State private var strength = 26.0
  @State private var status: FieldStatus.Status = .idle

  /// Persists only a user edit. Hydration (`onAppear`) and the rollback assign
  /// `openAccess` directly, so neither can issue a write — a failed redundant
  /// write could otherwise roll back into a request that reopens access.
  private var openAccessBinding: Binding<Bool> {
    Binding(
      get: { openAccess },
      set: { next in
        let previous = openAccess
        guard next != previous else { return }
        openAccess = next
        settingWrite(
          $status,
          rollback: { openAccess = previous },
          work: {
            try await env.profiles?.updateAppSettings(openAccess: next)
            await env.refreshAccount()
          }
        )
      }
    )
  }

  var body: some View {
    SettingsSection(title: "Owner") {
      SettingsRow(
        label: "Open access",
        detail: openAccess ? "Anyone can register and use the app." : "Only you can use the app."
      ) {
        Toggle("", isOn: openAccessBinding).labelsHidden().tint(VZ.accent)
      }
      Rectangle().fill(VZ.hair).frame(height: 1)
      VStack(alignment: .leading, spacing: 6) {
        SettingsRow(
          label: "Developer accent strength",
          detail: "Library-card corner field, \(Int(strength))%"
        ) { EmptyView() }
        Slider(
          value: $strength,
          in: Double(AppSettings.devAccentRange.lowerBound) ...
            Double(AppSettings.devAccentRange.upperBound),
          step: 1,
          onEditingChanged: { editing in
            if !editing {
              let previous = Double(env.appSettings.dev_accent_strength)
              settingWrite(
                $status,
                rollback: { strength = previous },
                work: {
                  try await env.profiles?.updateAppSettings(devAccentStrength: Int(strength))
                  // Library cards read `env.appSettings` — refresh so the new
                  // strength renders without a relaunch.
                  await env.refreshAccount()
                }
              )
            }
          }
        )
        .tint(VZ.accent)
      }
      FieldStatus(status: status)
    }
    .onAppear {
      openAccess = env.appSettings.open_access
      strength = Double(env.appSettings.dev_accent_strength)
    }
  }
}

// MARK: - About

struct AboutSection: View {
  var body: some View {
    SettingsSection(title: "About") {
      SettingsRow(label: "Version", detail: nil) {
        Text("v\(AppVersion.marketing) (\(AppVersion.build))").font(.vzBody(13)).monospacedDigit()
          .foregroundStyle(VZ.muted)
      }
      Rectangle().fill(VZ.hair).frame(height: 1)
      VStack(alignment: .leading, spacing: 4) {
        Text("Acknowledgements").font(.vzBody(15)).foregroundStyle(VZ.text)
        Text(VizionBrand.acknowledgements).font(.vzBody(11)).foregroundStyle(VZ.muted)
      }
      Rectangle().fill(VZ.hair).frame(height: 1)
      Text(
        """
        VIZION is a VASEY/AI product. \
        License and security policy live in the repository (LICENSE · SECURITY.md).
        """
      )
      .font(.vzBody(11)).foregroundStyle(VZ.muted)
    }
  }
}
