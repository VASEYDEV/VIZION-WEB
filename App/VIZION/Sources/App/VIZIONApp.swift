import SwiftUI

@main
struct VIZIONApp: App {
  @State private var environment = AppEnvironment()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(environment)
        .environment(environment.ui)
        .environment(environment.results)
        .environment(environment.toasts)
        .preferredColorScheme(environment.ui.theme.colorScheme)
        .tint(VZ.accent)
        .task { await environment.start() }
        .onOpenURL { url in Task { await environment.handle(url: url) } }
    }
  }
}
