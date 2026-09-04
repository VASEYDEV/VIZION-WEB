import SwiftUI
import VizionCore

/// The gate every screen hangs off (web: middleware + the (app) layout):
/// configuration → session → onboarding → owner's closed-access switch → app.
struct RootView: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    ZStack {
      AmbientBackground(reduced: env.ui.reducedEffects)
      Group {
        switch env.gate {
        case let .configMissing(message):
          ConfigMissingView(message: message)
        case .loading:
          ProgressView().tint(VZ.accent)
        case .signedOut:
          AuthGateView()
        case .needsPassword:
          SetPasswordView()
        case .closed:
          AccessClosedView()
        case .app:
          MainTabView()
        }
      }
      .transition(.opacity)
      ToastOverlay()
    }
    .animation(VZ.Motion.slideAnimation, value: env.gate)
  }
}

enum AppTab: Hashable {
  case enhance
  case library
  case settings
}

/// The three-tab shell (web: `BottomNav`). Tab icons are the web's own
/// 24-grid strokes rendered to template images.
struct MainTabView: View {
  @Environment(AppEnvironment.self) private var env
  @State private var tab: AppTab = .enhance

  var body: some View {
    TabView(selection: $tab) {
      Tab(value: .enhance) {
        EnhanceScreen()
      } label: {
        Label { Text("Enhance") } icon: { Image(uiImage: VZIcon.enhance.templateImage) }
      }
      Tab(value: .library) {
        LibraryScreen()
      } label: {
        Label { Text("Library") } icon: { Image(uiImage: VZIcon.library.templateImage) }
      }
      Tab(value: .settings) {
        SettingsScreen()
      } label: {
        Label { Text("Settings") } icon: { Image(uiImage: VZIcon.settings.templateImage) }
      }
    }
    .tint(VZ.accent)
    // `initial: true`: a link that arrived while signed out (or before this
    // view existed) is already pending when the modifier attaches.
    .onChange(of: env.pendingTab, initial: true) { _, next in
      if let next {
        tab = next
        env.pendingTab = nil
      }
    }
    .onChange(of: env.pendingPromptID, initial: true) { _, id in
      if id != nil {
        tab = .library
      }
    }
    .onChange(of: env.pendingDraft, initial: true) { _, draft in
      if draft != nil {
        tab = .enhance
      }
    }
  }
}

struct ConfigMissingView: View {
  var message: String

  var body: some View {
    ScreenColumn {
      VStack(spacing: 16) {
        BrandMark(width: 96)
        Text("Not configured")
          .font(.vzDisplay(28))
          .foregroundStyle(VZ.text)
        Text(message)
          .font(.vzBody(14))
          .foregroundStyle(VZ.muted)
          .multilineTextAlignment(.center)
        Text("See docs/runbooks/local-dev.md")
          .font(.vzMono(12))
          .foregroundStyle(VZ.muted)
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .vzGlass()
    }
  }
}

struct AccessClosedView: View {
  @Environment(AppEnvironment.self) private var env

  var body: some View {
    ScreenColumn {
      VStack(spacing: 12) {
        Text("Access is closed")
          .font(.vzDisplay(28))
          .foregroundStyle(VZ.text)
        Text(
          """
          The owner has temporarily closed VIZION to other accounts. \
          Your data is safe and will be here when access reopens.
          """
        )
        .font(.vzBody(14))
        .foregroundStyle(VZ.muted)
        .multilineTextAlignment(.center)
        Button("Sign out") { Task { await env.signOut() } }
          .buttonStyle(.secondary)
          .padding(.top, 8)
      }
      .padding(24)
      .frame(maxWidth: .infinity)
      .vzGlass()
    }
  }
}

extension VZIcon {
  /// Template UIImage for tab items (SwiftUI tab labels take images, not shapes).
  @MainActor var templateImage: UIImage {
    Self.imageCache.image(for: self)
  }

  @MainActor
  private final class ImageCache {
    private var images: [VZIcon: UIImage] = [:]

    func image(for icon: VZIcon) -> UIImage {
      if let cached = images[icon] {
        return cached
      }
      let size = CGSize(width: 24, height: 24)
      let renderer = UIGraphicsImageRenderer(size: size)
      let image = renderer.image { context in
        let path = UIBezierPath(cgPath: Path(svg: icon.commands).cgPath)
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor.black.setStroke()
        context.cgContext.setLineWidth(1.5)
        path.stroke()
      }
      let template = image.withRenderingMode(.alwaysTemplate)
      images[icon] = template
      return template
    }
  }

  @MainActor private static let imageCache = ImageCache()
}
