import Foundation

/// Markdown / JSON / plain-text exports of a result (web: `export.ts`).
public struct ExportData: Sendable, Hashable {
  public var input: String
  public var output: String
  public var rationale: String
  public var mode: EnhanceMode
  public var target: TargetModel
  public var modelUsed: String

  public init(
    input: String, output: String, rationale: String, mode: EnhanceMode, target: TargetModel,
    modelUsed: String
  ) {
    self.input = input
    self.output = output
    self.rationale = rationale
    self.mode = mode
    self.target = target
    self.modelUsed = modelUsed
  }
}

public enum ExportFormat: String, CaseIterable, Sendable, Identifiable {
  case markdown = "md"
  case json
  case text = "txt"

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .markdown: "Markdown"
    case .json: "JSON"
    case .text: "Text"
    }
  }

  public var fileExtension: String { rawValue }

  public var mimeType: String {
    switch self {
    case .markdown: "text/markdown"
    case .json: "application/json"
    case .text: "text/plain"
    }
  }

  public func render(_ d: ExportData) -> String {
    switch self {
    case .markdown: Exporters.markdown(d)
    case .json: Exporters.json(d)
    case .text: Exporters.text(d)
    }
  }
}

public enum Exporters {
  /// The human-facing heading uses the mode LABEL.
  public static func markdown(_ d: ExportData) -> String {
    [
      "# VIZION — \(d.mode.label) → \(d.target.label)",
      "",
      "## Input",
      "",
      "```",
      d.input,
      "```",
      "",
      "## Enhanced",
      "",
      "```",
      d.output,
      "```",
      "",
      "## What changed",
      "",
      d.rationale,
      "",
      "_Model: \(d.modelUsed)_",
      "",
    ].joined(separator: "\n")
  }

  /// The JSON export keeps the raw ids (a machine artifact whose stability
  /// outlives label renames). Key order matches the web export.
  public static func json(_ d: ExportData) -> String {
    let fields: [(String, String)] = [
      ("mode", d.mode.rawValue),
      ("target", d.target.rawValue),
      ("model", d.modelUsed),
      ("input", d.input),
      ("output", d.output),
      ("rationale", d.rationale),
    ]
    let body = fields.map { key, value in "  \"\(key)\": \(jsonString(value))" }
      .joined(separator: ",\n")
    return "{\n\(body)\n}"
  }

  public static func text(_ d: ExportData) -> String {
    "\(d.output)\n"
  }

  static func jsonString(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out + "\""
  }
}
