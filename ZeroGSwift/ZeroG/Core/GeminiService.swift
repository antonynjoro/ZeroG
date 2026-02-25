import Foundation
import GoogleGenerativeAI

// MARK: - Gemini Service

/// Optional Gemini API integration for grammar correction and formatting.
/// Replaces Python's `gemini.py` with native Swift async/await using the Google Generative AI SDK.
///
/// ## Privacy Note
/// This feature sends text to Google's servers for processing.
/// It is only activated when the user holds Control+Q during recording.
final class GeminiService {
    
    // MARK: Shared Instance
    
    /// Shared singleton. `nil` if no API key is configured.
    static var shared: GeminiService?
    
    // MARK: Configuration
    
    private let model: GenerativeModel
    
    /// The model name matching the Python version's configuration.
    private static let modelName = "gemini-2.0-flash-exp"
    
    // MARK: Initialization
    
    init(apiKey: String, systemInstruction: String) {
        self.model = GenerativeModel(
            name: Self.modelName,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
                temperature: 0.0,
                maxOutputTokens: 4096
            ),
            systemInstruction: ModelContent(parts: [.text(systemInstruction)])
        )
    }
    
    private static let apiKeyDefaultsKey = "GOOGLE_API_KEY"
    
    /// Initialize the shared instance from configuration.
    /// Checks UserDefaults first (set via menu bar), then environment variable.
    static func configure() {
        // Check UserDefaults first, then environment variable
        let apiKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)
            ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
        
        guard let apiKey, !apiKey.isEmpty else {
            print("[GeminiService] No API key found. Set one via the ZeroG menu bar. Gemini disabled.")
            return
        }
        
        configureWithKey(apiKey)
    }
    
    /// Configure with a specific API key (called from the settings dialog).
    static func configure(apiKey: String) {
        UserDefaults.standard.set(apiKey, forKey: apiKeyDefaultsKey)
        configureWithKey(apiKey)
        print("[GeminiService] API key saved and configured.")
    }
    
    /// Returns the currently stored API key (masked for display).
    static var storedKeyPreview: String? {
        guard let key = UserDefaults.standard.string(forKey: apiKeyDefaultsKey)
                ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
              !key.isEmpty else { return nil }
        let prefix = String(key.prefix(6))
        return "\(prefix)...\(String(key.suffix(4)))"
    }
    
    private static func configureWithKey(_ apiKey: String) {
        let systemInstruction: String
        if let promptURL = Bundle.main.url(forResource: "gemini_prompt", withExtension: "txt"),
           let promptContent = try? String(contentsOf: promptURL, encoding: .utf8) {
            systemInstruction = promptContent.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            systemInstruction = "Reformulate text as a professional document."
        }
        
        shared = GeminiService(apiKey: apiKey, systemInstruction: systemInstruction)
        print("[GeminiService] Configured with model: \(modelName)")
        
        Task.detached {
            await shared?.warmup()
        }
    }
    
    // MARK: - Processing
    
    /// Process raw transcription text through Gemini for polishing/formatting.
    func process(_ text: String) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text
        }
        
        do {
            let response = try await model.generateContent("Text: \(text)")
            
            if let processedText = response.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !processedText.isEmpty {
                
                #if DEBUG
                print("[GeminiService] Processed: '\(processedText.prefix(60))...'")
                #endif
                
                return processedText
            }
            
            return text
            
        } catch {
            #if DEBUG
            print("[GeminiService] Processing failed: \(error.localizedDescription)")
            #endif
            return text
        }
    }
    
    // MARK: - Private
    
    private func warmup() async {
        do {
            _ = try await model.generateContent("Warmup.")
            #if DEBUG
            print("[GeminiService] Warmup complete.")
            #endif
        } catch {
            #if DEBUG
            print("[GeminiService] Warmup failed (non-critical): \(error.localizedDescription)")
            #endif
        }
    }
}
