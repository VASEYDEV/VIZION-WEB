import Foundation

/// Refinement passes over a finished enhancement (web: REFINE_KINDS). The first
/// three are chips on a result; `answers` is a re-run of the original request
/// with the user's replies attached, offered by the Clarify questions card.
public enum RefineKind: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case shorter
  case detail
  case tone
  case answers

  public var id: String { rawValue }

  /// Chip label; `answers` has no chip.
  public var chipLabel: String? {
    switch self {
    case .shorter: "Make shorter"
    case .detail: "More detail"
    case .tone: "Keep my tone"
    case .answers: nil
    }
  }

  public static let chips: [RefineKind] = [.shorter, .detail, .tone]
}

public struct EnhanceRefine: Codable, Sendable, Hashable {
  public let kind: RefineKind
  /// Extra context the pass needs: the author's ORIGINAL for `tone`, the
  /// fenced Q&A block for `answers`.
  public let baseInput: String?

  public init(kind: RefineKind, baseInput: String? = nil) {
    self.kind = kind
    self.baseInput = baseInput
  }

  /// The Q&A block the `answers` pass sends as `baseInput` — the same shape
  /// the web composer builds (positional questions + answers).
  public static func answersBlock(questions: [String], answers: [String]) -> String {
    zip(questions, answers)
      .map { question, answer in
        "Q: \(question)\nA: \(answer.trimmingCharacters(in: .whitespacesAndNewlines))"
      }
      .joined(separator: "\n\n")
  }
}

/// POST /api/enhance body (web: EnhanceRequest in `use-enhance.ts`). Optionals
/// are OMITTED from the JSON when nil — synthesized Codable uses
/// `encodeIfPresent` — which is what the route expects: an absent knob is
/// inert, a `null` would be a 400.
public struct EnhanceRequest: Codable, Sendable, Hashable {
  /// Hard ceiling the route enforces (413 above it).
  public static let maxInputChars = 20_000
  public static let maxContextItems = 4
  public static let maxContextBlockChars = 2_000

  public var input: String
  public var mode: EnhanceMode
  /// Always a real roster id. Under Auto this is the FALLBACK — the server
  /// resolves the actual target and reports it back as `resolvedTarget`.
  public var target: TargetModel
  /// `true` to let the server pick. Never `false` on the wire (omitted instead).
  public var auto: Bool?
  public var autoPreference: AutoPreference?
  public var format: OutputFormat?
  public var length: LengthSetting?
  public var thinkingLevel: ThinkingLevel?
  public var refine: EnhanceRefine?
  public var mediaContext: [String]?

  public init(
    input: String,
    mode: EnhanceMode,
    target: TargetModel,
    auto: Bool = false,
    autoPreference: AutoPreference? = nil,
    format: OutputFormat? = nil,
    length: LengthSetting? = nil,
    thinkingLevel: ThinkingLevel? = nil,
    refine: EnhanceRefine? = nil,
    mediaContext: [String]? = nil
  ) {
    self.input = input
    self.mode = mode
    self.target = target
    self.auto = auto ? true : nil
    // The preference travels WITH the auto flag or not at all.
    self.autoPreference = auto ? autoPreference : nil
    // Mode-gated knobs: send only what the mode reads, so a stale selection
    // never rides along as noise.
    self.format = mode == .reformat ? format : nil
    self.length = mode.hasLengthControl ? length : nil
    self.thinkingLevel = thinkingLevel
    self.refine = refine
    self.mediaContext = (mediaContext?.isEmpty ?? true) ? nil : mediaContext
  }

  /// Client-side mirror of the route's pre-flight gates, so obviously bad
  /// requests fail with a sentence before a network round trip.
  public func validate() -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Provide a prompt to enhance." }
    if input.utf16.count > Self.maxInputChars {
      return "Prompt is too long (max \(Self.maxInputChars) characters)."
    }
    if let thinkingLevel, auto != true, !target.thinkingLadder.contains(thinkingLevel) {
      return "That thinking level isn't available for this model."
    }
    if let mediaContext {
      if mediaContext.count > Self.maxContextItems { return "Too many reference attachments." }
      if mediaContext.contains(where: { $0.utf16.count > Self.maxContextBlockChars }) {
        return "A reference description is too long."
      }
    }
    return nil
  }
}
