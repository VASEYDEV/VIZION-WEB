import SwiftUI
import VizionCore

/// The composer's attachment tray: one row per attachment with its role, the
/// per-item progress, the extracted description/text, and Insert/Remove.
struct AttachmentTrayView: View {
  @Bindable var model: EnhanceViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionCaption(text: "Attachments", icon: .paperclip)
      ForEach(model.attachments) { attachment in
        AttachmentRow(attachment: attachment, model: model)
      }
    }
  }
}

struct AttachmentRow: View {
  var attachment: EnhanceViewModel.Attachment
  @Bindable var model: EnhanceViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        thumbnail
        VStack(alignment: .leading, spacing: 4) {
          Text(MediaContext.sanitizeName(attachment.name)).font(.vzBody(13, .medium)).foregroundStyle(VZ.text)
          HStack(spacing: 6) {
            roleMenu
            if attachment.role == .generate {
              genMenu
            }
          }
          Text(attachment.stepLabel)
            .font(.vzBody(11))
            .foregroundStyle({ if case .error = attachment.status { VZ.flare } else { VZ.muted } }())
          if attachment.ephemeral {
            Text("Analyzed without keeping").font(.vzBody(10)).foregroundStyle(VZ.muted)
          }
        }
        Spacer(minLength: 0)
        Button { model.remove(attachment.id) } label: { IconView(.close, size: 16) }
          .buttonStyle(.quiet).accessibilityLabel("Remove attachment")
      }
      if attachment.status == .ready, let payload = payloadText, !payload.isEmpty {
        Text(payload).font(.vzBody(12)).foregroundStyle(VZ.muted).lineLimit(4)
        HStack {
          Button(attachment.inserted ? "Inserted" : insertLabel) { model.insert(attachment.id) }
            .buttonStyle(.secondaryInline)
            .disabled(attachment.inserted)
          if let usage = attachment.usage {
            Text("\(usage.estimated == true ? "≈" : "")$\(usage.costUsd, specifier: "%.4f")")
              .font(.vzBody(11)).monospacedDigit().foregroundStyle(VZ.muted)
          }
        }
      } else if attachment.status == .ready, attachment.role == .generate {
        Button(attachment.inserted ? "Built" : "Build generation prompt") { model.insert(attachment.id) }
          .buttonStyle(.secondaryInline).disabled(attachment.inserted)
      }
    }
    .padding(12)
    .vzGlass(cornerRadius: VZ.Radius.control)
  }

  private var thumbnail: some View {
    Group {
      if let data = attachment.thumbnail, let image = UIImage(data: data) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        IconView(.paperclip, size: 20).foregroundStyle(VZ.muted)
      }
    }
    .frame(width: 48, height: 48)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var roleMenu: some View {
    Menu {
      ForEach(AttachmentRole.roles(for: attachment.kind)) { role in
        Button {
          model.setRole(role, for: attachment.id)
        } label: {
          Label(role.label, systemImage: role == attachment.role ? "checkmark" : "")
        }
      }
    } label: {
      ChipLabel(text: attachment.role.label, selected: true)
    }
    .accessibilityHint(attachment.role.blurb)
  }

  private var genMenu: some View {
    Menu {
      ForEach(GenTarget.options(for: attachment.kind)) { target in
        Button(target.label) { model.setGenTarget(target, for: attachment.id) }
      }
    } label: {
      ChipLabel(text: attachment.genTarget.label, selected: false)
    }
  }

  private var payloadText: String? {
    switch attachment.role {
    case .reference, .describe: attachment.description
    case .extract: attachment.extractedText
    case .style: attachment.attrs.map(MediaContext.styleSnippet)
    case .generate: nil
    }
  }

  private var insertLabel: String {
    switch attachment.role {
    case .extract: "Insert text"
    case .style: "Insert style"
    default: "Insert description"
    }
  }
}
