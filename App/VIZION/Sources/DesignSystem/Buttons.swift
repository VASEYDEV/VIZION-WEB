import SwiftUI

/// The single primary action per surface: Void ink on a Laser fill — never
/// Laser text on light (§6 contrast law).
struct LaserButtonStyle: ButtonStyle {
  var fullWidth = true

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.vzBody(15, .medium))
      .foregroundStyle(VZ.onLaser)
      .padding(.horizontal, 20)
      .frame(minHeight: 48)
      .frame(maxWidth: fullWidth ? .infinity : nil)
      .background(
        VZ.laser,
        in: RoundedRectangle(cornerRadius: VZ.Radius.control, style: .continuous)
      )
      .shadow(color: VZ.laserGlow, radius: configuration.isPressed ? 4 : 14, y: 4)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(VZ.Motion.quickAnimation, value: configuration.isPressed)
  }
}

/// Glass secondary action.
struct SecondaryButtonStyle: ButtonStyle {
  var fullWidth = true
  var tint: Color = VZ.text

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.vzBody(15, .medium))
      .foregroundStyle(tint)
      .padding(.horizontal, 16)
      .frame(minHeight: 44)
      .frame(maxWidth: fullWidth ? .infinity : nil)
      .vzGlass(cornerRadius: VZ.Radius.control)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(VZ.Motion.quickAnimation, value: configuration.isPressed)
  }
}

/// The press state every tappable surface carries (web: `.pressable`).
struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(VZ.Motion.quickAnimation, value: configuration.isPressed)
  }
}

/// A quiet text link in Silver that lifts to Chalk.
struct QuietButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.vzBody(14))
      .foregroundStyle(configuration.isPressed ? VZ.text : VZ.muted)
      .frame(minHeight: VZ.tapTarget)
      .contentShape(Rectangle())
  }
}

extension ButtonStyle where Self == LaserButtonStyle {
  static var laser: LaserButtonStyle {
    LaserButtonStyle()
  }

  static var laserInline: LaserButtonStyle {
    LaserButtonStyle(fullWidth: false)
  }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
  static var secondary: SecondaryButtonStyle {
    SecondaryButtonStyle()
  }

  static var secondaryInline: SecondaryButtonStyle {
    SecondaryButtonStyle(fullWidth: false)
  }

  static var destructive: SecondaryButtonStyle {
    SecondaryButtonStyle(tint: VZ.flare)
  }
}

extension ButtonStyle where Self == PressableStyle {
  static var pressable: PressableStyle {
    PressableStyle()
  }
}

extension ButtonStyle where Self == QuietButtonStyle {
  static var quiet: QuietButtonStyle {
    QuietButtonStyle()
  }
}

/// A rail chip / segment: Laser fill with on-laser ink when selected, glass otherwise.
struct ChipLabel: View {
  var text: String
  var selected: Bool
  var icon: VZIcon?

  var body: some View {
    HStack(spacing: 6) {
      if let icon {
        IconView(icon, size: 14)
      }
      Text(text)
    }
    .font(.vzBody(13, .medium))
    .foregroundStyle(selected ? VZ.onLaser : VZ.text)
    .padding(.horizontal, 12)
    .frame(minHeight: 36)
    .background(
      Capsule().fill(selected ? VZ.laser : VZ.surface)
    )
    .overlay(Capsule().strokeBorder(selected ? Color.clear : VZ.hair, lineWidth: 1))
  }
}
