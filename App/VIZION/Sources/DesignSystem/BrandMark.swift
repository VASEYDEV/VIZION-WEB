import SwiftUI
import VizionCore

/// The VIZION brand mark — the master glyph drawn on the theme-aware accent
/// ink. Sized by width; the 1024×892.8 aspect sets the height.
struct BrandMark: View {
  var width: CGFloat = 32
  var color: Color = VZ.accent

  private var aspect: CGFloat {
    BrandGlyph.viewBoxWidth / BrandGlyph.viewBoxHeight
  }

  var body: some View {
    SVGShape(
      commands: BrandGlyph.commands,
      viewBox: CGSize(width: BrandGlyph.viewBoxWidth, height: BrandGlyph.viewBoxHeight)
    )
    .fill(color, style: FillStyle(eoFill: true))
    .frame(width: width, height: width / aspect)
    .accessibilityHidden(true)
  }
}

/// The wordmark: V I Z N in Chalk, the "IO" in the accent ink. Display face.
struct Wordmark: View {
  var size: CGFloat = 26

  var body: some View {
    HStack(spacing: 0) {
      Text("VIZ").foregroundStyle(VZ.text)
      Text("IO").foregroundStyle(VZ.accent)
      Text("N").foregroundStyle(VZ.text)
    }
    .font(.vzDisplay(size))
    .tracking(size * 0.04)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("VIZION")
  }
}

/// Header lockup: the mark to the LEFT of the wordmark, cap-band balanced.
struct BrandLockup: View {
  var body: some View {
    HStack(spacing: 8) {
      BrandMark(width: 30).offset(y: -1)
      Wordmark(size: 26)
    }
  }
}

/// Brand + version micro-pills.
struct BrandPills: View {
  var body: some View {
    HStack(spacing: 8) {
      Pill {
        Circle().fill(VZ.accent).frame(width: 6, height: 6)
        Text(VizionBrand.company)
      }
      Pill { Text("v\(AppVersion.marketing)") }
    }
  }

  private struct Pill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
      HStack(spacing: 6) { content }
        .font(.vzBody(10, .medium, relativeTo: .caption2))
        .textCase(.uppercase)
        .tracking(1)
        .foregroundStyle(VZ.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(VZ.surface))
        .overlay(Capsule().strokeBorder(VZ.hair, lineWidth: 1))
    }
  }
}

enum AppVersion {
  static var marketing: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
  }

  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  }
}
