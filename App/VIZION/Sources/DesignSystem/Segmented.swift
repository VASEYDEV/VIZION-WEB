import SwiftUI

/// Inline segmented control — a small, closed set of mutually exclusive
/// choices, all visible. The active segment fills with Laser + on-laser ink.
/// `fill` lays the options out as equal columns across the container (the
/// composer's Shape/Depth rails); otherwise intrinsic width (Settings' theme).
struct VZSegmented<ID: Hashable>: View {
  var options: [(id: ID, label: String)]
  @Binding var selection: ID?
  var fill = false
  /// Re-picking the active segment clears it (the rails' "whichever fits" route back).
  var clearsOnReselect = false
  var accessibilityLabel: String

  @Namespace private var lens

  var body: some View {
    let row = HStack(spacing: 2) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        let selected = option.id == selection
        Button {
          if selected, clearsOnReselect {
            selection = nil
          } else {
            selection = option.id
          }
        } label: {
          Text(option.label)
            .font(.vzBody(13, .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(selected ? VZ.onLaser : VZ.muted)
            .padding(.horizontal, fill ? 4 : 12)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: 36)
            .background {
              if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(VZ.laser)
                  .matchedGeometryEffect(id: "lens", in: lens)
              }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(4)
    .vzGlass(cornerRadius: VZ.Radius.control)
    .animation(VZ.Motion.slideAnimation, value: selection)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibilityLabel)

    if fill {
      row.frame(maxWidth: .infinity)
    } else {
      row.fixedSize(horizontal: true, vertical: false)
    }
  }
}
