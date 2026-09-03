import Foundation

/// Coarse processing ladder every provider emits (web: STREAM_STEPS).
public enum StreamStep: String, Codable, Sendable {
  case queued
  case connecting
  case generating
  case parsing
  case diffing

  public var label: String {
    switch self {
    case .queued: "Queued"
    case .connecting: "Reaching the model…"
    case .generating: "Generating…"
    case .parsing: "Checking the result…"
    case .diffing: "Building the diff…"
    }
  }
}

/// The SSE wire contract between /api/enhance and the client (web:
/// `stream-events.ts`). Frames ride the POST body as `data: {json}\n\n`.
public enum EnhanceStreamEvent: Sendable, Hashable {
  case status(step: StreamStep?, label: String)
  case thinking(text: String)
  case delta(text: String)
  /// `snapshot` marks a provider PLACEHOLDER frame (tokenOut ~1-4 before
  /// generation); its absence means a real measurement.
  case usage(tokenIn: Int, tokenOut: Int, costUsd: Double?, snapshot: Bool)
  case done(EnhanceResult)
  case error(status: Int, message: String, notConfigured: Bool, capReached: Bool)
}

extension EnhanceStreamEvent: Decodable {
  private enum CodingKeys: String, CodingKey {
    case type, step, label, text, tokenIn, tokenOut, costUsd, snapshot, result, status, error,
      notConfigured, capReached
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "status":
      let step = try c.decodeIfPresent(String.self, forKey: .step).flatMap(StreamStep.init(rawValue:))
      let label = try c.decodeIfPresent(String.self, forKey: .label) ?? step?.label ?? ""
      self = .status(step: step, label: label)
    case "thinking":
      self = .thinking(text: try c.decodeIfPresent(String.self, forKey: .text) ?? "")
    case "delta":
      self = .delta(text: try c.decodeIfPresent(String.self, forKey: .text) ?? "")
    case "usage":
      self = .usage(
        tokenIn: try c.decodeIfPresent(Int.self, forKey: .tokenIn) ?? 0,
        tokenOut: try c.decodeIfPresent(Int.self, forKey: .tokenOut) ?? 0,
        costUsd: try c.decodeIfPresent(Double.self, forKey: .costUsd),
        snapshot: try c.decodeIfPresent(Bool.self, forKey: .snapshot) ?? false
      )
    case "done":
      self = .done(try c.decode(EnhanceResult.self, forKey: .result))
    case "error":
      self = .error(
        status: try c.decodeIfPresent(Int.self, forKey: .status) ?? 502,
        message: try c.decodeIfPresent(String.self, forKey: .error) ?? "Enhancement failed.",
        notConfigured: try c.decodeIfPresent(Bool.self, forKey: .notConfigured) ?? false,
        capReached: try c.decodeIfPresent(Bool.self, forKey: .capReached) ?? false
      )
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: c, debugDescription: "Unknown stream event type \(type)"
      )
    }
  }
}

/// Incremental SSE frame parser. Handles frames split across network chunks
/// and multiple frames per chunk; garbled frames are skipped (the `done` /
/// `error` contract is what callers act on).
public struct SSEParser: Sendable {
  private var buffer: [UInt8] = []
  private let decoder = JSONDecoder()

  public init() {}

  /// Feed raw bytes; returns every complete event they finished.
  public mutating func feed(_ bytes: some Sequence<UInt8>) -> [EnhanceStreamEvent] {
    buffer.append(contentsOf: bytes)
    var events: [EnhanceStreamEvent] = []
    while let range = Self.frameSeparator(in: buffer) {
      let frame = Array(buffer[..<range.lowerBound])
      buffer.removeSubrange(..<range.upperBound)
      events.append(contentsOf: parse(frame: frame))
    }
    return events
  }

  /// Flush a trailing frame with no terminating blank line (a stream that
  /// closed mid-frame). Returns whatever parsed.
  public mutating func finish() -> [EnhanceStreamEvent] {
    defer { buffer.removeAll() }
    return buffer.isEmpty ? [] : parse(frame: buffer)
  }

  /// One-shot convenience for a fully buffered body.
  public static func parse(_ data: Data) -> [EnhanceStreamEvent] {
    var parser = SSEParser()
    var events = parser.feed(data)
    events.append(contentsOf: parser.finish())
    return events
  }

  private func parse(frame: [UInt8]) -> [EnhanceStreamEvent] {
    guard let text = String(bytes: frame, encoding: .utf8) else { return [] }
    var events: [EnhanceStreamEvent] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine[...]
      guard line.hasPrefix("data:") else { continue }
      let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      guard let data = payload.data(using: .utf8),
        let event = try? decoder.decode(EnhanceStreamEvent.self, from: data)
      else { continue }
      events.append(event)
    }
    return events
  }

  /// The `\n\n` (or `\r\n\r\n`) that ends a frame.
  private static func frameSeparator(in bytes: [UInt8]) -> Range<Int>? {
    guard bytes.count >= 2 else { return nil }
    var i = 0
    while i < bytes.count - 1 {
      if bytes[i] == 0x0A, bytes[i + 1] == 0x0A { return i..<(i + 2) }
      if i < bytes.count - 3, bytes[i] == 0x0D, bytes[i + 1] == 0x0A, bytes[i + 2] == 0x0D,
        bytes[i + 3] == 0x0A
      {
        return i..<(i + 4)
      }
      i += 1
    }
    return nil
  }
}

/// Live progress of an in-flight enhance stream (web: EnhanceStreamState in
/// `use-enhance.ts`). Pure, so the monotonic-counter rules are unit-tested.
public struct EnhanceStreamState: Sendable, Hashable {
  public var active = false
  public var step = ""
  public var partialOutput = ""
  /// Live counters, monotonic by construction: a provider's early low-ball
  /// snapshot cannot pin the ticker and a late frame cannot walk it backwards.
  public var tokenIn = 0
  public var tokenOut = 0
  public var costUsd = 0.0
  /// True once a usage frame arrived that was NOT a pre-generation snapshot.
  /// The char estimator stands down at that point.
  public var usageMeasured = false

  public init() {}

  public static let idle = EnhanceStreamState()

  public static func started() -> EnhanceStreamState {
    var state = EnhanceStreamState()
    state.active = true
    state.step = StreamStep.queued.label
    return state
  }

  /// ~4 chars/token — the only thing moving until a measurement lands.
  public static func estimateTokens(chars: Int) -> Int {
    Int((Double(chars) / 4).rounded(.up))
  }

  public mutating func apply(_ event: EnhanceStreamEvent) {
    switch event {
    case let .status(_, label):
      step = label
    case let .thinking(text):
      step = text
    case let .delta(text):
      partialOutput += text
      if !usageMeasured {
        tokenOut = Swift.max(tokenOut, Self.estimateTokens(chars: partialOutput.utf16.count))
      }
    case let .usage(newIn, newOut, newCost, snapshot):
      // A real measurement REPLACES; a snapshot may only raise.
      let measured = !snapshot
      tokenIn = Swift.max(newIn, tokenIn)
      tokenOut = measured ? newOut : Swift.max(newOut, tokenOut)
      if let newCost {
        costUsd = measured ? newCost : Swift.max(newCost, costUsd)
      }
      usageMeasured = usageMeasured || measured
    case .done, .error:
      break
    }
  }
}
