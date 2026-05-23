import Foundation

// MARK: - Configuration

/// Application configuration management.
/// Replaces Python's `.env` + `dotenv` with native Swift mechanisms.
///
/// ## Configuration Sources (priority order)
/// 1. Environment variables (for development)
/// 2. UserDefaults (for user preferences)
/// 3. Defaults (hardcoded fallbacks)
enum Config {
    
    // MARK: Debug
    
    /// Whether debug logging is enabled.
    static var isDebugEnabled: Bool {
        ProcessInfo.processInfo.environment["DEBUG"]?.lowercased() == "true"
            || UserDefaults.standard.bool(forKey: "DEBUG")
    }
    
    // MARK: Gemini API
    
    /// Google API key for Gemini integration.
    static var googleAPIKey: String? {
        ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "GOOGLE_API_KEY")
    }
    
    // MARK: Audio
    
    /// Safety-only silence threshold (RMS amplitude below which is considered true silence).
    static let silenceThreshold: Float = 0.003

    /// Seconds of continuous true silence before auto-stop.
    static let silenceDuration: TimeInterval = 12.0

    /// Seconds to keep recording after key release to capture trailing speech.
    static let recordingTailDuration: TimeInterval = 0.5
    
    // MARK: Whisper Model
    
    /// The WhisperKit model variant to use.
    static let whisperModel: String = "large-v3-v20240930_turbo"
    
    // MARK: Load
    
    /// Load configuration from `.env` file if present (development convenience).
    static func load() {
        loadDotEnv()
    }
    
    // MARK: - Private
    
    /// Simple `.env` file parser for development convenience.
    private static func loadDotEnv() {
        let envPath = Bundle.main.bundlePath
            .components(separatedBy: "/")
            .dropLast(1) // Remove .app bundle
            .joined(separator: "/")
            + "/.env"
        
        guard FileManager.default.fileExists(atPath: envPath),
              let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return
        }
        
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            
            setenv(key, value, 1)
        }
        
        #if DEBUG
        print("[Config] Loaded .env file from: \(envPath)")
        #endif
    }
}
