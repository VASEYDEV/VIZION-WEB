import Foundation

/// One diff token run (web: DiffSegment).
public struct DiffSegment: Codable, Sendable, Hashable {
  public enum Op: String, Codable, Sendable {
    case equal
    case added
    case removed
  }

  public var op: Op
  public var text: String

  public init(op: Op, text: String) {
    self.op = op
    self.text = text
  }
}

/// The final enhance result — the `done` event's payload (web: EnhanceResult).
/// Optional fields ride the envelope additively; absent keys decode as nil.
public struct EnhanceResult: Codable, Sendable, Hashable {
  public struct Usage: Codable, Sendable, Hashable {
    public var todayCost: Double
    public var capUsd: Double

    public init(todayCost: Double, capUsd: Double) {
      self.todayCost = todayCost
      self.capUsd = capUsd
    }
  }

  public var output: String
  public var rationale: String
  /// nil when the pair exceeded the server's diff budget — render plain text.
  public var diff: [DiffSegment]?
  public var tokenIn: Int
  public var tokenOut: Int
  public var modelUsed: String
  public var costUsd: Double
  public var usage: Usage
  public var assumptions: [String]?
  public var targetNotes: String?
  public var title: String?
  /// Clarify only — questions whose answers would sharpen the request.
  public var questions: [String]?
  public var salvaged: Bool?
  /// The model hit its output ceiling: the text is INCOMPLETE.
  public var truncated: Bool?
  public var usageEstimated: Bool?
  /// Which model Auto picked — present ONLY on an auto-routed run.
  public var resolvedTarget: TargetModel?
  /// Raw wire value; unknown reasons render as nothing.
  public var resolvedReason: String?

  public init(
    output: String,
    rationale: String,
    diff: [DiffSegment]?,
    tokenIn: Int,
    tokenOut: Int,
    modelUsed: String,
    costUsd: Double,
    usage: Usage,
    assumptions: [String]? = nil,
    targetNotes: String? = nil,
    title: String? = nil,
    questions: [String]? = nil,
    salvaged: Bool? = nil,
    truncated: Bool? = nil,
    usageEstimated: Bool? = nil,
    resolvedTarget: TargetModel? = nil,
    resolvedReason: String? = nil
  ) {
    self.output = output
    self.rationale = rationale
    self.diff = diff
    self.tokenIn = tokenIn
    self.tokenOut = tokenOut
    self.modelUsed = modelUsed
    self.costUsd = costUsd
    self.usage = usage
    self.assumptions = assumptions
    self.targetNotes = targetNotes
    self.title = title
    self.questions = questions
    self.salvaged = salvaged
    self.truncated = truncated
    self.usageEstimated = usageEstimated
    self.resolvedTarget = resolvedTarget
    self.resolvedReason = resolvedReason
  }

  public var resolvedReasonLabel: String? {
    AutoRouteReason.label(forRaw: resolvedReason)
  }

  /// Fraction of today's cap consumed after this run, 0…∞.
  public var capFraction: Double {
    usage.capUsd > 0 ? usage.todayCost / usage.capUsd : 0
  }
}

/// A gate or stream failure from /api/enhance or /api/media.
public struct EnhanceFailure: Error, Sendable, Hashable, LocalizedError {
  public let message: String
  /// HTTP status of a pre-stream failure, the `error` event's status, or 0
  /// for a deliberate cancel (the UI ignores status 0).
  public let status: Int
  public let notConfigured: Bool
  public let capReached: Bool

  public init(message: String, status: Int, notConfigured: Bool = false, capReached: Bool = false) {
    self.message = message
    self.status = status
    self.notConfigured = notConfigured
    self.capReached = capReached
  }

  public var isCancelled: Bool {
    status == 0
  }

  public var errorDescription: String? {
    message
  }

  public static let cancelled = EnhanceFailure(message: "Cancelled.", status: 0)

  /// The one user-facing copy for a provider whose key isn't deployed.
  public static let notConfiguredMessage =
    "This model isn't configured yet — add its API key on the server to enable it."

  /// The copy the UI shows for a failure — `notConfigured` gets the shared
  /// sentence, everything else its own message.
  public var displayMessage: String {
    notConfigured ? Self.notConfiguredMessage : message
  }
}

/// JSON shape of a pre-stream (non-200) failure: `{ error, notConfigured?, capReached? }`.
public struct APIErrorBody: Codable, Sendable {
  public var error: String?
  public var notConfigured: Bool?
  public var capReached: Bool?

  public init(error: String?, notConfigured: Bool? = nil, capReached: Bool? = nil) {
    self.error = error
    self.notConfigured = notConfigured
    self.capReached = capReached
  }

  public func failure(status: Int, fallback: String) -> EnhanceFailure {
    EnhanceFailure(
      message: error ?? fallback,
      status: status,
      notConfigured: notConfigured ?? false,
      capReached: capReached ?? false
    )
  }
}
