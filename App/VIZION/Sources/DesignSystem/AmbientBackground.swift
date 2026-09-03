import SwiftUI

/// The NEBULA ground (web: `AmbientNebula`): a quiet accent-and-silver bloom
/// field behind every screen. Reduced Effects (a user knob) and the system's
/// Reduce Motion both collapse it to the flat ground.
struct AmbientBackground: View {
  var reduced: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase = 0.0

  var body: some View {
    ZStack {
      VZ.ground.ignoresSafeArea()
      if !reduced {
        GeometryReader { proxy in
          let size = proxy.size
          let drift = reduceMotion ? 0 : phase
          ZStack {
            bloom(VZ.accent.opacity(0.16), diameter: size.width * 0.9)
              .position(x: size.width * (0.2 + 0.08 * sin(drift)), y: size.height * (0.18 + 0.05 * cos(drift * 0.8)))
            bloom(VZ.muted.opacity(0.14), diameter: size.width * 1.0)
              .position(x: size.width * (0.85 - 0.06 * cos(drift * 0.7)), y: size.height * (0.45 + 0.06 * sin(drift * 0.6)))
            bloom(Color(hex: 0x4B7896, alpha: 0.11), diameter: size.width * 0.7)
              .position(x: size.width * (0.5 + 0.1 * sin(drift * 0.5)), y: size.height * (0.85 - 0.04 * cos(drift)))
            bloom(VZ.accent.opacity(0.09), diameter: size.width * 0.5)
              .position(x: size.width * 0.75, y: size.height * (0.1 + 0.03 * sin(drift * 1.1)))
          }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
          guard !reduceMotion else { return }
          while !Task.isCancelled {
            withAnimation(.linear(duration: 18)) { phase += .pi / 2 }
            try? await Task.sleep(for: .seconds(18))
          }
        }
      }
    }
  }

  private func bloom(_ color: Color, diameter: CGFloat) -> some View {
    Circle()
      .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: diameter / 2))
      .frame(width: diameter, height: diameter)
      .blur(radius: diameter * 0.08)
  }
}
