import SwiftUI
import UIKit
import VizionCore

/// The seven locked roles + derived inks (web: `tokens.css`), as dynamic
/// colours that follow the trait collection. Contrast law: text on a Laser
/// fill is ALWAYS `onLaser` (fixed dark) in both themes; Laser is never used
/// as text or a thin stroke on a light surface (1.09:1 FAIL) — use `accent`.
enum VZ {
  // MARK: Page ground

  /// `--void` — page bg stop. Chalk canvas on light.
  static let ground = Color.vz(light: 0xEEF0F4, dark: 0x0F1012)
  static let ground2 = Color.vz(light: 0xE3E6EC, dark: 0x0E1013)
  static let lift = Color.vz(light: 0xFFFFFF, dark: 0x16181D)

  // MARK: Text

  /// `--chalk` — primary text.
  static let text = Color.vz(light: 0x0F1012, dark: 0xF2F3F6)
  /// `--silver` — muted text (AA on both canvases).
  static let muted = Color.vz(light: 0x565B63, dark: 0xB9BCC5)

  // MARK: Surfaces

  static let surface = Color.vz(light: 0xFFFFFF, dark: 0x2B2D33, lightAlpha: 0.72, darkAlpha: 0.55)
  static let glass = Color.vz(light: 0xFFFFFF, dark: 0x2B2D33, lightAlpha: 0.82, darkAlpha: 0.72)
  static let chrome = Color.vz(light: 0xFFFFFF, dark: 0x101216, lightAlpha: 0.42, darkAlpha: 0.45)
  static let onyx = Color.vz(light: 0xFFFFFF, dark: 0x2B2D33)
  static let hair = Color.vz(light: 0x0F1012, dark: 0xB9BCC5, lightAlpha: 0.12, darkAlpha: 0.20)
  static let sheen = Color.vz(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.07)

  // MARK: Accent

  /// `--laser` — accent FILL + primary action. Constant across themes.
  static let laser = Color(hex: 0xC7FD26)
  /// `--on-laser` — the dark ink that sits ON laser.
  static let onLaser = Color(hex: 0x0E1013)
  /// `--accent-ink` — Laser used AS TEXT/ICON: Laser on dark, deep green on light.
  static let accent = Color.vz(light: 0x526810, dark: 0xC7FD26)
  static let laserGlow = Color(hex: 0xC7FD26, alpha: 0.25)

  // MARK: Semantic

  /// `--flare` — error / destructive (text/border only, never a fill).
  static let flare = Color.vz(light: 0xC81D10, dark: 0xFF5247)
  static let pulse = Color(hex: 0x3DD68C)
  static let amber = Color(hex: 0xFFC24B)
  static let pulseInk = Color.vz(light: 0x0D7040, dark: 0x3DD68C)
  static let amberInk = Color.vz(light: 0x8A5200, dark: 0xFFC24B)
  /// The dial's ultra tier — the only colour in the track.
  static let ultra = Color.vz(light: 0x7C3AED, dark: 0xB47AFF)
  static let ultraHi = Color.vz(light: 0x4C1D95, dark: 0xD9C2FF)

  static func developer(_ developer: Developer) -> Color {
    Color(hexString: developer.accentHex)
  }

  static func tone(_ tone: DialTone) -> Color {
    switch tone {
    case .faint: muted.opacity(0.16)
    case .silver: muted.opacity(0.34)
    case .steel: muted.opacity(0.58)
    case .ultra: ultra
    }
  }

  // MARK: Geometry (4px base, 8-pt rhythm)

  enum Radius {
    /// `rounded-2xl` — panels, cards, sheets.
    static let panel: CGFloat = 16
    /// `rounded-xl` — controls, inputs, buttons.
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
  }

  enum Motion {
    static let quick: Double = 0.15
    static let slide: Double = 0.30
    static var quickAnimation: Animation {
      .easeOut(duration: quick)
    }

    static var slideAnimation: Animation {
      .timingCurve(0.16, 1, 0.3, 1, duration: slide)
    }
  }

  /// `--bottom-nav-h` (the tab bar itself adds the home-indicator inset).
  static let bottomNavHeight: CGFloat = 64
  static let floatGap: CGFloat = 12
  static let columnMaxWidth: CGFloat = 640
  static let tapTarget: CGFloat = 44
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha
    )
  }

  init(hexString: String) {
    var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") {
      s.removeFirst()
    }
    let value = UInt32(s, radix: 16) ?? 0x7D858E
    self.init(hex: value)
  }

  /// A theme-swapped role token: the light value on the light canvas, the
  /// dark value on Void. Resolved per trait collection, so it follows the
  /// per-view `preferredColorScheme` and the system setting alike.
  static func vz(
    light: UInt32,
    dark: UInt32,
    lightAlpha: Double = 1,
    darkAlpha: Double = 1
  ) -> Color {
    Color(
      uiColor: UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        return UIColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
      }
    )
  }
}

extension UIColor {
  convenience init(hex: UInt32, alpha: Double = 1) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: CGFloat(alpha)
    )
  }
}

extension AppTheme {
  var colorScheme: ColorScheme? {
    switch self {
    case .dark: .dark
    case .light: .light
    case .system: nil
    }
  }
}
