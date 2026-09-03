import Foundation

/// Attachment kinds and the exact MIME allowlist of the `media` bucket (web:
/// `media/types.ts`). The client admits what the server will store.
public enum MediaKind: String, CaseIterable, Codable, Sendable, Hashable {
  case image
  case video
  case audio

  public var allowedMIME: [String] {
    switch self {
    case .image: ["image/png", "image/jpeg", "image/webp", "image/gif"]
    case .video: ["video/mp4", "video/webm", "video/quicktime"]
    case .audio: ["audio/mpeg", "audio/wav", "audio/ogg", "audio/mp4"]
    }
  }

  public static var allAllowedMIME: [String] { allCases.flatMap(\.allowedMIME) }

  public static func kind(forMIME mime: String) -> MediaKind? {
    let lower = mime.lowercased()
    return allCases.first { $0.allowedMIME.contains(lower) }
  }

  /// File extension for a MIME type — the `p_ext` the reserve RPC takes.
  public static func fileExtension(forMIME mime: String) -> String {
    switch mime.lowercased() {
    case "image/png": "png"
    case "image/jpeg": "jpg"
    case "image/webp": "webp"
    case "image/gif": "gif"
    case "video/mp4": "mp4"
    case "video/webm": "webm"
    case "video/quicktime": "mov"
    case "audio/mpeg": "mp3"
    case "audio/wav": "wav"
    case "audio/ogg": "ogg"
    case "audio/mp4": "m4a"
    default: "bin"
    }
  }
}

/// Attributes VIZION "reads" from an attached reference. Audio never reaches a
/// model — only file metadata is read.
public struct MediaAttributes: Codable, Sendable, Hashable {
  public var subject: String?
  public var composition: String?
  public var palette: [String]?
  public var lighting: String?
  public var style: String?
  public var mood: String?
  /// Prose visual description (2–4 sentences), paste-ready for a prompt.
  public var description: String?
  public var width: Int?
  public var height: Int?
  public var durationSec: Double?
  /// "proxy" | "ondevice" — where the attributes came from.
  public var source: String

  public init(
    subject: String? = nil, composition: String? = nil, palette: [String]? = nil,
    lighting: String? = nil, style: String? = nil, mood: String? = nil,
    description: String? = nil, width: Int? = nil, height: Int? = nil, durationSec: Double? = nil,
    source: String = "proxy"
  ) {
    self.subject = subject
    self.composition = composition
    self.palette = palette
    self.lighting = lighting
    self.style = style
    self.mood = mood
    self.description = description
    self.width = width
    self.height = height
    self.durationSec = durationSec
    self.source = source
  }
}

/// Every attachment declares WHY it's attached. `reference` is the default — a
/// screenshot attached as evidence must never be inferred into a generation
/// prompt; "generate" is an explicit choice with an explicit engine picker.
public enum AttachmentRole: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case reference
  case extract
  case describe
  case style
  case generate

  public var id: String { rawValue }

  public static let `default`: AttachmentRole = .reference

  public var label: String {
    switch self {
    case .reference: "Reference"
    case .extract: "Extract text"
    case .describe: "Describe"
    case .style: "Style reference"
    case .generate: "Generate similar"
    }
  }

  public var blurb: String {
    switch self {
    case .reference: "Gives the model visual context for your text prompt."
    case .extract: "Transcribes legible text so you can insert it."
    case .describe: "Writes an editable description you can insert."
    case .style: "Captures palette, lighting, and mood — not the subject."
    case .generate: "Builds a generation prompt for an engine you pick."
    }
  }

  public var kinds: [MediaKind] {
    switch self {
    case .reference, .generate: [.image, .video, .audio]
    case .extract, .describe, .style: [.image, .video]
    }
  }

  /// Roles an attachment of this kind can take.
  public static func roles(for kind: MediaKind) -> [AttachmentRole] {
    allCases.filter { $0.kinds.contains(kind) }
  }

  /// Which /api/media analysis intent produces this role's attrs/text. nil
  /// for roles that need no model pass (audio, generate-only).
  public var analysisIntent: MediaAnalysisIntent? {
    switch self {
    case .reference, .describe, .generate: .reference
    case .style: .style
    case .extract: .extractText
    }
  }
}

/// `/api/media` analysis intents.
public enum MediaAnalysisIntent: String, Codable, Sendable, Hashable {
  case reference
  case describe
  case style
  case extractText = "extract_text"
}

/// Generation engines we can format for.
public enum GenTarget: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case midjourney
  case runway
  case sora
  case kling
  case audio

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .midjourney: "Midjourney"
    case .runway: "Runway"
    case .sora: "Sora"
    case .kling: "Kling"
    case .audio: "Audio spec"
    }
  }

  public var kind: MediaKind {
    switch self {
    case .midjourney: .image
    case .runway, .sora, .kling: .video
    case .audio: .audio
    }
  }

  public static func `default`(for kind: MediaKind) -> GenTarget {
    switch kind {
    case .image: .midjourney
    case .video: .runway
    case .audio: .audio
    }
  }

  public static func options(for kind: MediaKind) -> [GenTarget] {
    allCases.filter { $0.kind == kind }
  }
}

/// POST /api/media body.
public struct MediaAnalysisRequest: Codable, Sendable, Hashable {
  /// Rough decoded-size guard the route enforces (413 above it).
  public static let maxImageBytes = 5 * 1024 * 1024

  public var dataUrl: String
  public var target: TargetModel?
  public var intent: MediaAnalysisIntent?
  public var auto: Bool?
  public var autoPreference: AutoPreference?

  public init(
    dataUrl: String, target: TargetModel?, intent: MediaAnalysisIntent?, auto: Bool = false,
    autoPreference: AutoPreference? = nil
  ) {
    self.dataUrl = dataUrl
    self.target = target
    self.intent = intent
    self.auto = auto ? true : nil
    self.autoPreference = auto ? autoPreference : nil
  }

  /// `data:<mime>;base64,<payload>`
  public static func dataURL(mime: String, base64: String) -> String {
    "data:\(mime);base64,\(base64)"
  }
}

public struct MediaAnalysisUsage: Codable, Sendable, Hashable {
  public var target: TargetModel?
  public var tokenIn: Int
  public var tokenOut: Int
  public var costUsd: Double
  public var todayCost: Double
  public var capUsd: Double
  public var estimated: Bool?
}

/// POST /api/media response — attributes for the reference/describe/style
/// intents, `text` for extract_text.
public struct MediaAnalysisResponse: Codable, Sendable, Hashable {
  public var intent: MediaAnalysisIntent?
  public var attributes: MediaAttributes?
  public var description: String?
  public var text: String?
  public var modelUsed: String
  /// Set when analysis ran on a different target than the one aimed at.
  public var fallbackFrom: TargetModel?
  public var usage: MediaAnalysisUsage
}
