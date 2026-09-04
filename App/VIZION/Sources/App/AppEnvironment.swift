import Foundation
import Observation
import Supabase
import VizionCore

/// Composition root: configuration, the Supabase-backed services, the two
/// persisted stores, the session, and the gate every screen hangs off.
@MainActor
@Observable
final class AppEnvironment {
  enum Gate: Equatable {
    case configMissing(String)
    case loading
    case signedOut
    case needsPassword
    case closed
    case app
  }

  let ui = UIStore()
  let results = EnhanceViewStore()
  let toasts = ToastCenter()

  private(set) var config: AppConfig?
  private(set) var configProblem: String?
  private(set) var supabase: SupabaseService?
  private(set) var api: VizionAPI?
  private(set) var library: LibraryRepository?
  private(set) var profiles: ProfileRepository?

  private(set) var session: SupabaseService.SessionInfo?
  private(set) var profile: Profile?
  private(set) var appSettings: AppSettings = .defaults
  private(set) var sessionResolved = false
  /// A `?draft=` that arrived while the app was signed out or mid-launch.
  var pendingDraft: String?
  var pendingPromptID: String?
  var pendingAuthError: String?
  /// A tab the app should switch to (deep link, draft resume, New prompt);
  /// consumed by `MainTabView`, including a value set before it existed.
  var pendingTab: AppTab?

  private var observing = false

  init() {
    switch AppConfig.load() {
    case let .success(config):
      self.config = config
      let supabase = SupabaseService(config: config)
      self.supabase = supabase
      api = VizionAPI(
        baseURL: config.apiBaseURL,
        tokenProvider: { try await supabase.accessToken() }
      )
      library = LibraryRepository(client: supabase.client)
      profiles = ProfileRepository(client: supabase.client)
    case let .failure(problem):
      configProblem = problem.description
    }
  }

  var gate: Gate {
    if let configProblem {
      return .configMissing(configProblem)
    }
    guard sessionResolved else { return .loading }
    guard let session else { return .signedOut }
    if let profile, profile.needsPasswordOnboarding {
      return .needsPassword
    }
    if !appSettings.open_access, !isOwner(session.userID) {
      return .closed
    }
    return .app
  }

  var isOwner: Bool {
    session.map { isOwner($0.userID) } ?? false
  }

  private func isOwner(_ userID: String) -> Bool {
    appSettings.isOwner(userID: userID)
  }

  // MARK: Lifecycle

  func start() async {
    guard let supabase, !observing else { return }
    observing = true
    session = supabase.currentSession
    if session != nil {
      await refreshAccount()
    }
    sessionResolved = true
    for await change in supabase.authChanges {
      switch change.event {
      case .signedIn, .tokenRefreshed, .userUpdated, .initialSession:
        let had = session != nil
        session = supabase.currentSession
        if session != nil, !had || change.event == .userUpdated {
          await refreshAccount()
        }
      case .signedOut:
        session = nil
        profile = nil
      default:
        break
      }
    }
  }

  /// Re-read the profile + owner settings and hydrate the UI store (once per
  /// account switch — Settings is authoritative for what the app opens on).
  func refreshAccount() async {
    guard let profiles, let session else { return }
    do {
      async let profileTask = profiles.profile()
      async let settingsTask = profiles.appSettings()
      let (profile, settings) = try await (profileTask, settingsTask)
      self.profile = profile
      appSettings = settings
      ui.hydrate(profile: profile, userID: session.userID)
      results.adopt(userID: session.userID)
    } catch {
      // Offline at launch: keep the last-known profile and let the screens
      // report their own failures.
      ui.hydrate(profile: profile, userID: session.userID)
    }
  }

  func signOut() async {
    ui.saveNow()
    try? await supabase?.signOut()
    session = nil
    profile = nil
  }

  // MARK: URL intake

  func handle(url: URL) async {
    guard let link = DeepLink.parse(url) else { return }
    switch link {
    case let .enhance(draft):
      pendingDraft = draft
      pendingTab = .enhance
    case let .prompt(id):
      pendingPromptID = id
      pendingTab = .library
    case .library:
      pendingTab = .library
    case .settings:
      pendingTab = .settings
    case let .authCallback(callback):
      do {
        try await supabase?.completeSignIn(from: callback)
      } catch {
        pendingAuthError = error.localizedDescription
      }
    case let .authError(message):
      pendingAuthError = message
    }
  }
}
