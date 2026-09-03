import Foundation

/// Brand + product constants shared by every screen.
public enum VizionBrand {
  public static let productName = "VIZION"
  public static let company = "VASEY/AI"
  public static let tagline = "Transform any prompt for the engine that's about to receive it."
  public static let footerLine = "Multi-Model Prompt Studio"
  public static let productionCredit = "A VASEY/AI Production"
  public static let companySite = URL(string: "https://vasey.ai")!
  public static let multimediaSite = URL(string: "https://vaseymultimedia.com")!
  /// The deployed web app — the model proxy the app talks to (ADR-0002).
  public static let defaultAPIBase = URL(string: "https://vizion-io.vercel.app")!
  public static let repository = URL(string: "https://github.com/vaseydev/vizion-web")!
  public static let acknowledgements =
    "Type: Bebas Neue, Reddit Sans, and JetBrains Mono (SIL Open Font License). Developer marks via thesvg.org and Simple Icons. Built on Supabase."
}
