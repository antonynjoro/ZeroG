import Foundation
import FoundationModels

// MARK: - Polish Service

/// On-device text polish via **Apple Foundation Models** — the system LLM behind
/// Apple Intelligence. No network, no downloaded model, nothing leaves the Mac.
///
/// Requires macOS 26 + Apple Silicon + Apple Intelligence enabled. This façade is
/// callable from any deployment target (the app floor is macOS 14): the real work
/// sits behind `@available(macOS 26, *)`, and `isAvailable` / `unavailableReason`
/// let the UI disable itself with a reason on machines that can't run it.
enum PolishService {

    /// Whether on-device polish can run right now.
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return FoundationPolish.isAvailable }
        return false
    }

    /// A human-readable reason polish is unavailable, or `nil` when available.
    static var unavailableReason: String? {
        if #available(macOS 26.0, *) { return FoundationPolish.unavailableReason }
        return "Polish needs macOS 26 with Apple Intelligence."
    }

    /// Polish `text` on-device. Throws `PolishError` if unavailable or generation
    /// fails. Returns the original text unchanged if the model yields nothing.
    static func polish(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard #available(macOS 26.0, *) else {
            throw PolishError.unavailable("Polish needs macOS 26 with Apple Intelligence.")
        }
        return try await FoundationPolish.polish(trimmed)
    }
}

enum PolishError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .failed(let message):     return message
        }
    }
}

// MARK: - Foundation Models backend (macOS 26+)

@available(macOS 26.0, *)
private enum FoundationPolish {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use Polish."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing its model. Try again shortly."
        case .unavailable:
            return "On-device polish is unavailable right now."
        }
    }

    static func polish(_ text: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions())
        do {
            let response = try await session.respond(to: text)
            let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? text : out
        } catch {
            throw PolishError.failed(error.localizedDescription)
        }
    }

    /// The polish system prompt (ghostwriter/editor; em-dash-free, output-only).
    private static func instructions() -> String {
        if let url = Bundle.main.url(forResource: Config.polishPromptResource, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "Clean up the dictated text: fix grammar, punctuation and capitalization while keeping the original meaning and wording. Do not use em dashes. Output only the corrected text."
    }
}
