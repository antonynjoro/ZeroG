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
    
    /// Initialize the Gemini service with an API key and system instruction.
    ///
    /// - Parameters:
    ///   - apiKey: Google AI API key.
    ///   - systemInstruction: Prompt template loaded from `gemini_prompt.txt`.
    init(apiKey: String, systemInstruction: String) {
        self.model = GenerativeModel(
            name: Self.modelName,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
                temperature: 0.0,
                maxOutputTokens: 4096,
                responseMIMEType: "text/plain"
            ),
            systemInstruction: ModelContent(
                role: "system",
                parts: [.text(systemInstruction)]
            )
        )
    }
    
    /// Initialize the shared instance from configuration (API key and prompt file).
    /// Call once at app startup.
    static func configure() {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
                ?? UserDefaults.standard.string(forKey: "GOOGLE_API_KEY"),
              !apiKey.isEmpty else {
            #if DEBUG
            print("[GeminiService] No GOOGLE_API_KEY found. Gemini processing disabled.")
            #endif
            return
        }
        
        // Load the system instruction / prompt template
        let systemInstruction: String
        if let promptURL = Bundle.main.url(forResource: "gemini_prompt", withExtension: "txt"),
           let promptContent = try? String(contentsOf: promptURL, encoding: .utf8) {
            systemInstruction = promptContent.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            systemInstruction = "Reformulate text as a professional document."
        }
        
        shared = GeminiService(apiKey: apiKey, systemInstruction: systemInstruction)
        
        #if DEBUG
        print("[GeminiService] Configured with model: \(modelName)")
        #endif
        
        // Warmup (non-blocking)
        Task {
            await shared?.warmup()
        }
    }
    
    // MARK: - Processing
    
    /// Process raw transcription text through Gemini for polishing/formatting.
    ///
    /// - Parameter text: Raw transcription text.
    /// - Returns: Polished text, or the original text if processing fails.
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
    
    /// Send a lightweight warmup request to prime the HTTP connection.
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
