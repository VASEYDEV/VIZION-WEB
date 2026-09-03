import Foundation

/// The sixteen target models (web: TARGET_MODELS). Raw values are the wire ids
/// AND the `model_target` Postgres enum labels — renaming one requires a
/// migration on the server. Declaration order IS display order: grouped by
/// developer (Developer.allCases order), best model first within each.
public enum TargetModel: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
  case fable5 = "fable_5"
  case opus5 = "opus_5"
  case sonnet5 = "sonnet_5"
  case gpt56Sol = "gpt_5_6_sol"
  case gpt56Terra = "gpt_5_6_terra"
  case gpt56Luna = "gpt_5_6_luna"
  case deepseekV4 = "deepseek_v4"
  case gemini36Flash = "gemini_3_6_flash"
  case museSpark11 = "muse_spark_1_1"
  case minimaxM3 = "minimax_m3"
  case mistralLarge3 = "mistral_large_3"
  case kimiK3 = "kimi_k3"
  case sonarPro = "sonar_pro"
  case qwen38Max = "qwen3_8_max"
  case grok45 = "grok_4_5"
  case glm52 = "glm_5_2"

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .fable5: "Fable 5"
    case .opus5: "Opus 5"
    case .sonnet5: "Sonnet 5"
    case .gpt56Sol: "GPT-5.6 Sol"
    case .gpt56Terra: "GPT-5.6 Terra"
    case .gpt56Luna: "GPT-5.6 Luna"
    case .deepseekV4: "DeepSeek V4"
    case .gemini36Flash: "Gemini 3.6 Flash"
    case .museSpark11: "Muse Spark 1.1"
    case .minimaxM3: "MiniMax M3"
    case .mistralLarge3: "Mistral Large 3"
    case .kimiK3: "Kimi K3"
    case .sonarPro: "Sonar Pro"
    case .qwen38Max: "Qwen3.8 Max"
    case .grok45: "Grok 4.5"
    case .glm52: "GLM-5.2"
    }
  }

  public var developer: Developer {
    switch self {
    case .fable5, .opus5, .sonnet5: .anthropic
    case .gpt56Sol, .gpt56Terra, .gpt56Luna: .openai
    case .deepseekV4: .deepseek
    case .gemini36Flash: .google
    case .museSpark11: .meta
    case .minimaxM3: .minimax
    case .mistralLarge3: .mistral
    case .kimiK3: .moonshot
    case .sonarPro: .perplexity
    case .qwen38Max: .qwen
    case .grok45: .xai
    case .glm52: .zai
    }
  }

  /// Per-target thinking levels, exactly as each provider's API accepts them
  /// (web: TARGET_THINKING_LEVELS). Empty = no per-request knob = no dial.
  public var thinkingLadder: [ThinkingLevel] {
    switch self {
    case .fable5, .opus5, .sonnet5, .qwen38Max: [.low, .medium, .high, .xhigh, .max]
    case .gpt56Sol, .gpt56Terra, .gpt56Luna, .grok45: [.low, .medium, .high]
    case .gemini36Flash: [.minimal, .low, .medium, .high]
    case .deepseekV4, .museSpark11, .minimaxM3, .mistralLarge3, .kimiK3, .sonarPro, .glm52: []
    }
  }

  public var hasThinkingDial: Bool { !thinkingLadder.isEmpty }

  /// The device-local fallback the web UI store starts on.
  public static let `default`: TargetModel = .opus5

  /// Every id the roster has ever renamed away from → its replacement (web:
  /// LEGACY_TARGET_IDS). A stale persisted selection would 400 on /api/enhance.
  public static let legacyIDs: [String: TargetModel] = [
    "gpt_5_5": .gpt56Sol,
    "gemini_pro_3_1": .gemini36Flash,
    "opus_4_8": .opus5,
    "llama_4_maverick": .museSpark11,
    "minimax_m2_7": .minimaxM3,
    "kimi_k2_6": .kimiK3,
    "gemini_3_5_thinking": .gemini36Flash,
    "qwen3_7_max": .qwen38Max,
  ]

  /// Current id or a legacy one → the live target; nil for anything unknown.
  public static func resolve(_ raw: String?) -> TargetModel? {
    guard let raw else { return nil }
    return TargetModel(rawValue: raw) ?? legacyIDs[raw]
  }

  /// Display label for a raw stored id — falls back to the raw id.
  public static func label(forRaw raw: String) -> String {
    resolve(raw)?.label ?? raw
  }

  /// Developer for a raw stored id (legacy ids keep their mark), nil when unknown.
  public static func developer(forRaw raw: String) -> Developer? {
    resolve(raw)?.developer
  }

  /// The roster grouped under developer headers, in locked order.
  public static var grouped: [(developer: Developer, models: [TargetModel])] {
    Developer.allCases.compactMap { developer in
      let models = allCases.filter { $0.developer == developer }
      return models.isEmpty ? nil : (developer, models)
    }
  }
}
