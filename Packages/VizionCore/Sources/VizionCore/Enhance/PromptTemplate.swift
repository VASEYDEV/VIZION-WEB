import Foundation

/// Starter prompts for the blank page (web: `templates.ts`). Static seeds a
/// user edits, each deliberately under-specified so the enhancement has
/// something to do.
public struct PromptTemplate: Sendable, Identifiable, Hashable {
  public let id: String
  public let title: String
  public let hint: String
  public let mode: EnhanceMode
  public let text: String

  public static let all: [PromptTemplate] = [
    PromptTemplate(
      id: "explain", title: "Explain a concept", hint: "Teach me something, pitched at a level",
      mode: .expand,
      text: "Explain how database indexes work to someone who writes SQL but has never tuned a query."
    ),
    PromptTemplate(
      id: "code-review", title: "Review some code", hint: "Ask for a critique with priorities",
      mode: .expand, text: "Review this function and tell me what's wrong with it."
    ),
    PromptTemplate(
      id: "rewrite-tone", title: "Rewrite in a different tone", hint: "Same content, different register",
      mode: .reformat, text: "Rewrite this announcement so it sounds warmer and less corporate."
    ),
    PromptTemplate(
      id: "summarize", title: "Summarize a long document", hint: "Say what kind of summary you want",
      mode: .clarify, text: "Summarize this report."
    ),
    PromptTemplate(
      id: "brainstorm", title: "Brainstorm options", hint: "Generate alternatives with constraints",
      mode: .expand, text: "Give me some ideas for names for a prompt-engineering app."
    ),
    PromptTemplate(
      id: "image", title: "Describe an image to generate", hint: "Turn a rough visual idea into a prompt",
      mode: .target, text: "A lighthouse at dusk, dramatic and moody."
    ),
    PromptTemplate(
      id: "extract", title: "Extract structured data", hint: "Pull fields out of messy text",
      mode: .reformat,
      text: "Pull the names, dates, and amounts out of this text and give me a table."
    ),
    PromptTemplate(
      id: "debug", title: "Debug an error", hint: "Get a diagnosis, not just a guess",
      mode: .clarify, text: "My build fails with a module-not-found error. What's wrong?"
    ),
  ]
}
