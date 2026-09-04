import Foundation

/// Output shapes for Reformat (web: `formats.ts`). Reformat is about SHAPE,
/// Adapt is about IDIOM. Choosing one is optional — nil keeps "whichever fits".
public enum OutputFormat: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case json
  case markdown
  case steps
  case fewshot
  case xml

  public var id: String {
    rawValue
  }

  public var label: String {
    switch self {
    case .json: "JSON"
    case .markdown: "Markdown"
    case .steps: "Steps"
    case .fewshot: "Few-shot"
    case .xml: "XML"
    }
  }
}
