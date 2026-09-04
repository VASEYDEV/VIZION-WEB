import AuthenticationServices
import Foundation
import Supabase
import UIKit
import VizionCore

/// The one place the app touches supabase-swift's auth surface. Session
/// persistence is the SDK's default Keychain store; JWTs refresh through the
/// SDK before a request goes out (`accessToken()`), so the Vercel API never
/// sees an expired token from a healthy client (ADR-0003).
///
/// API-surface note: written against supabase-swift 2.x. If the resolved
/// package renames a signature, this file is the only one to reconcile.
final class SupabaseService: Sendable {
  let client: SupabaseClient

  init(config: AppConfig) {
    client = SupabaseClient(
      supabaseURL: config.supabaseURL,
      supabaseKey: config.supabaseAnonKey,
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          redirectToURL: DeepLink.authCallbackURL,
          flowType: .pkce
        )
      )
    )
  }

  // MARK: Session

  struct SessionInfo: Sendable, Equatable {
    let userID: String
    let email: String?
    let newEmail: String?
    let accessToken: String
    /// When the auth user was created — a sign-in that MINTED the account has
    /// this within seconds of now (see `AppEnvironment.purgeIfMintedWhileClosed`).
    let createdAt: Date?

    init(_ session: Session) {
      userID = session.user.id.uuidString.lowercased()
      email = session.user.email
      newEmail = session.user.newEmail
      accessToken = session.accessToken
      createdAt = session.user.createdAt
    }
  }

  /// The current session, refreshed by the SDK when it is about to expire.
  func session() async throws -> SessionInfo {
    try await SessionInfo(client.auth.session)
  }

  /// A fresh access token for the Vercel API's Bearer header.
  func accessToken() async throws -> String {
    try await client.auth.session.accessToken
  }

  var currentSession: SessionInfo? {
    client.auth.currentSession.map(SessionInfo.init)
  }

  /// SIGNED_IN / SIGNED_OUT / TOKEN_REFRESHED / USER_UPDATED … as they happen.
  var authChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
    client.auth.authStateChanges
  }

  // MARK: Sign-in

  /// Magic link (the default entry). `shouldCreateUser: false` under closed
  /// access — Supabase then rejects unknown addresses.
  func sendMagicLink(email: String, allowSignup: Bool) async throws {
    try await client.auth.signInWithOTP(
      email: email,
      redirectTo: DeepLink.authCallbackURL,
      shouldCreateUser: allowSignup
    )
  }

  func signIn(email: String, password: String) async throws {
    _ = try await client.auth.signIn(email: email, password: password)
  }

  enum OAuthProvider: String, CaseIterable, Sendable {
    case google
    case github

    var provider: Provider {
      switch self {
      case .github: .github
      case .google: .google
      }
    }

    var label: String {
      switch self {
      case .github: "Continue with GitHub"
      case .google: "Continue with Google"
      }
    }
  }

  /// OAuth through the system web-auth session (PKCE): the provider's consent
  /// page opens in an ASWebAuthenticationSession, Supabase redirects back to
  /// `vizion://auth/callback?code=…`, and the code is exchanged here.
  @MainActor
  func signIn(with provider: OAuthProvider) async throws {
    let url = try client.auth.getOAuthSignInURL(
      provider: provider.provider,
      redirectTo: DeepLink.authCallbackURL
    )
    let callback = try await WebAuthSession.run(url: url, callbackScheme: DeepLink.scheme)
    _ = try await client.auth.session(from: callback)
  }

  /// Sign in with Apple, natively: the identity token Apple issued to this
  /// app goes straight to Supabase, which verifies it against Apple's keys and
  /// the nonce, then mints (or resumes) the session — no web-auth session, no
  /// redirect (ADR-0006). The bundle id must be an authorised client id on the
  /// Apple provider (runbook `supabase-config.md`).
  func signInWithApple(idToken: String, nonce: String) async throws {
    _ = try await client.auth.signInWithIdToken(
      credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
    )
  }

  /// A magic link / OAuth return that arrived through `onOpenURL` instead of
  /// the web-auth session (the link was opened from Mail).
  func completeSignIn(from url: URL) async throws {
    _ = try await client.auth.session(from: url)
  }

  func signOut() async throws {
    try await client.auth.signOut()
  }

  // MARK: Credential + identity

  func updatePassword(_ password: String) async throws {
    _ = try await client.auth.update(user: UserAttributes(password: password))
  }

  /// Supabase sends a confirmation to the new address; the change applies once confirmed.
  func updateEmail(_ email: String) async throws {
    _ = try await client.auth.update(user: UserAttributes(email: email))
  }
}

/// ASWebAuthenticationSession bridged to async/await, presented from the key
/// window. `prefersEphemeralWebBrowserSession` stays false so a provider the
/// user is already signed into in Safari needs no second consent.
@MainActor
enum WebAuthSession {
  private final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
  }

  private static let context = ContextProvider()
  /// The in-flight session. ASWebAuthenticationSession must be RETAINED for
  /// the whole flow — released early it can end without ever calling the
  /// completion handler, leaving the continuation (and the sign-in form) stuck.
  private static var active: ASWebAuthenticationSession?

  static func run(url: URL, callbackScheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: callbackScheme
      ) { callback, error in
        Task { @MainActor in WebAuthSession.active = nil }
        if let callback {
          continuation.resume(returning: callback)
        } else if let error = error as? ASWebAuthenticationSessionError,
                  error.code == .canceledLogin {
          continuation.resume(throwing: CancellationError())
        } else {
          continuation.resume(throwing: error ?? URLError(.unknown))
        }
      }
      session.presentationContextProvider = context
      session.prefersEphemeralWebBrowserSession = false
      active = session
      if !session.start() {
        active = nil
        continuation.resume(throwing: URLError(.cannotConnectToHost))
      }
    }
  }
}
