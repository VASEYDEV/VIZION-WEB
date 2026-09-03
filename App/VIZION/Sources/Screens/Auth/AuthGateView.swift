import SwiftUI
import VizionCore

/// Auth gate (web: `/sign-in`): the brand hero, the three auth methods, the
/// brand/version pills, and the footer — over the ambient ground. No DIY
/// auth: Supabase Auth only.
struct AuthGateView: View {
  @Environment(AppEnvironment.self) private var env
  @State private var openAccess = true

  var body: some View {
    ScrollView {
      VStack(spacing: 32) {
        Spacer(minLength: 24)
        AuthHero()
        SignInForm(registrationClosed: !openAccess)
        Spacer(minLength: 16)
        VizionFooter()
      }
      .frame(maxWidth: 360)
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .task {
      // Owner switch: when access is closed the magic-link path must not mint
      // NEW accounts. Readable pre-auth (the web reads it the same way).
      if let settings = try? await env.profiles?.appSettings() { openAccess = settings.open_access }
    }
  }
}

struct AuthHero: View {
  var body: some View {
    VStack(spacing: 16) {
      BrandMark(width: 144)
      Wordmark(size: 40).accessibilityAddTraits(.isHeader)
      Text(VizionBrand.tagline)
        .font(.vzBody(14))
        .foregroundStyle(VZ.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 280)
      BrandPills()
    }
  }
}

struct SignInForm: View {
  enum Status: Equatable {
    case idle
    case sending
    case sent(String)
    case error(String)
  }

  var registrationClosed: Bool

  @Environment(AppEnvironment.self) private var env
  @State private var email = ""
  @State private var password = ""
  @State private var withPassword = false
  @State private var status: Status = .idle
  @FocusState private var focus: Field?

  private enum Field { case email, password }

  private var busy: Bool { status == .sending }

  var body: some View {
    VStack(spacing: 12) {
      if case let .sent(address) = status {
        sentCard(address)
      } else {
        form
      }
      if let pending = env.pendingAuthError {
        Text(Self.errorCopy(pending))
          .font(.vzBody(13))
          .foregroundStyle(VZ.flare)
          .multilineTextAlignment(.center)
          .onTapGesture { env.pendingAuthError = nil }
      }
    }
    .frame(maxWidth: 300)
  }

  private var form: some View {
    VStack(spacing: 12) {
      ForEach(SupabaseService.OAuthProvider.allCases, id: \.self) { provider in
        Button {
          Task { await signIn(with: provider) }
        } label: {
          HStack(spacing: 12) {
            ProviderMark(provider: provider, size: 18)
            Text(provider.label)
          }
        }
        .buttonStyle(.secondary)
        .disabled(busy)
      }

      HStack(spacing: 12) {
        Rectangle().fill(VZ.hair).frame(height: 1)
        Text("or").font(.vzBody(12)).foregroundStyle(VZ.muted)
        Rectangle().fill(VZ.hair).frame(height: 1)
      }
      .accessibilityHidden(true)

      TextField("you@example.com", text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(withPassword ? .next : .send)
        .multilineTextAlignment(.center)
        .vzInputFont()
        .vzField()
        .focused($focus, equals: .email)
        .onSubmit { if withPassword { focus = .password } else { Task { await submitEmail() } } }
        .accessibilityLabel("Email address")

      if withPassword {
        SecureField("Password", text: $password)
          .textContentType(.password)
          .submitLabel(.go)
          .multilineTextAlignment(.center)
          .vzInputFont()
          .vzField()
          .focused($focus, equals: .password)
          .onSubmit { Task { await submitEmail() } }
      }

      Button {
        Task { await submitEmail() }
      } label: {
        Text(busy ? (withPassword ? "Signing in…" : "Sending…") : (withPassword ? "Sign in" : "Email me a magic link"))
      }
      .buttonStyle(.laser)
      .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)

      Button(withPassword ? "Use a magic link instead" : "Have a password? Sign in with it") {
        withPassword.toggle()
        status = .idle
      }
      .buttonStyle(.quiet)

      if registrationClosed {
        Text("New registrations are currently closed. Existing accounts can still sign in.")
          .font(.vzBody(12))
          .foregroundStyle(VZ.muted)
          .multilineTextAlignment(.center)
      }

      if case let .error(message) = status {
        Text(message)
          .font(.vzBody(13))
          .foregroundStyle(VZ.flare)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isStaticText)
      }
    }
  }

  private func sentCard(_ address: String) -> some View {
    VStack(spacing: 8) {
      Text("Check your email")
        .font(.vzDisplay(24))
        .foregroundStyle(VZ.text)
      Text("We sent a magic link to ")
        .font(.vzBody(14)).foregroundStyle(VZ.muted)
        + Text(address).font(.vzBody(14, .medium)).foregroundStyle(VZ.text)
        + Text(". Open it on this device to continue.").font(.vzBody(14)).foregroundStyle(VZ.muted)
      Button("Use a different email") { status = .idle }
        .buttonStyle(.quiet)
        .foregroundStyle(VZ.accent)
    }
    .multilineTextAlignment(.center)
    .padding(20)
    .frame(maxWidth: .infinity)
    .vzGlass()
  }

  private func submitEmail() async {
    guard let supabase = env.supabase else { return }
    let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !address.isEmpty else { return }
    status = .sending
    do {
      if withPassword {
        try await supabase.signIn(email: address, password: password)
        status = .idle
      } else {
        try await supabase.sendMagicLink(email: address, allowSignup: !registrationClosed)
        status = .sent(address)
      }
    } catch {
      let message = error.localizedDescription
      let closed = message.range(of: "sign-?ups?|signup", options: [.regularExpression, .caseInsensitive]) != nil
      status = .error(closed ? "New registrations are currently closed." : message)
    }
  }

  private func signIn(with provider: SupabaseService.OAuthProvider) async {
    guard let supabase = env.supabase else { return }
    status = .sending
    do {
      try await supabase.signIn(with: provider)
      status = .idle
    } catch is CancellationError {
      // Backed out of the consent screen — every control returns to idle.
      status = .idle
    } catch {
      status = .error(error.localizedDescription)
    }
  }

  /// Human copy for the machine slugs the auth callback emits.
  static func errorCopy(_ raw: String) -> String {
    switch raw {
    case "missing_code": "That sign-in link was incomplete — request a fresh one."
    case "invalid_link", "otp_expired": "That sign-in link is invalid or has expired — request a fresh one."
    case "access_denied": "Sign-in was cancelled at the provider."
    default: raw.replacingOccurrences(of: "+", with: " ")
    }
  }
}

/// Magic-link onboarding: convert a passwordless entry into a durable
/// email+password credential, then advance into the studio.
struct SetPasswordView: View {
  @Environment(AppEnvironment.self) private var env
  @State private var password = ""
  @State private var confirm = ""
  @State private var error: String?
  @State private var saving = false

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Spacer(minLength: 40)
        AuthHero()
        VStack(spacing: 12) {
          Text("Set a password")
            .font(.vzDisplay(24))
            .foregroundStyle(VZ.text)
          SecureField("New password", text: $password)
            .textContentType(.newPassword)
            .multilineTextAlignment(.center)
            .vzInputFont().vzField()
          SecureField("Confirm password", text: $confirm)
            .textContentType(.newPassword)
            .multilineTextAlignment(.center)
            .vzInputFont().vzField()
          Text(PasswordRule.text)
            .font(.vzBody(12)).foregroundStyle(VZ.muted).multilineTextAlignment(.center)
          Button(saving ? "Saving…" : "Set password & continue") { Task { await save() } }
            .buttonStyle(.laser)
            .disabled(saving)
          if let error {
            Text(error).font(.vzBody(13)).foregroundStyle(VZ.flare).multilineTextAlignment(.center)
          }
          Button("Sign out") { Task { await env.signOut() } }.buttonStyle(.quiet)
        }
        .frame(maxWidth: 300)
        VizionFooter()
      }
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private func save() async {
    if let weak = PasswordRule.validate(password) {
      error = weak
      return
    }
    guard password == confirm else {
      error = "Passwords don't match."
      return
    }
    guard let supabase = env.supabase, let profiles = env.profiles else { return }
    saving = true
    defer { saving = false }
    do {
      try await supabase.updatePassword(password)
      try await profiles.setPasswordSet()
      await env.refreshAccount()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
