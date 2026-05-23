import Foundation
import Testing
@testable import ZeroG

@Suite(.serialized)
struct ConfigTests {
    @Test("Config exposes expected audio and model defaults")
    func defaultConstants() {
        #expect(Config.silenceThreshold == 0.003)
        #expect(Config.silenceDuration == 12.0)
        #expect(Config.recordingTailDuration == 0.5)
        #expect(Config.whisperModel == "large-v3-v20240930_turbo")
    }

    @Test("Debug defaults to false without environment or defaults")
    func debugDefaultsToFalse() {
        let defaults = UserDefaults.standard
        let previousDefault = defaults.object(forKey: "DEBUG")
        let previousEnvironment = getenv("DEBUG").map { String(cString: $0) }

        defaults.removeObject(forKey: "DEBUG")
        unsetenv("DEBUG")
        defer {
            restore(previousDefault, forKey: "DEBUG")
            restoreEnvironment(previousEnvironment, key: "DEBUG")
        }

        #expect(Config.isDebugEnabled == false)
    }

    @Test("Debug can be enabled through UserDefaults")
    func debugCanBeEnabledWithUserDefaults() {
        let defaults = UserDefaults.standard
        let previousDefault = defaults.object(forKey: "DEBUG")
        let previousEnvironment = getenv("DEBUG").map { String(cString: $0) }
        unsetenv("DEBUG")
        defer {
            restore(previousDefault, forKey: "DEBUG")
            restoreEnvironment(previousEnvironment, key: "DEBUG")
        }

        defaults.set(true, forKey: "DEBUG")

        #expect(Config.isDebugEnabled == true)
    }

    @Test("Google API key reads from UserDefaults when present")
    func googleAPIKeyReadsUserDefaults() {
        let defaults = UserDefaults.standard
        let previousDefault = defaults.object(forKey: "GOOGLE_API_KEY")
        let previousEnvironment = getenv("GOOGLE_API_KEY").map { String(cString: $0) }
        unsetenv("GOOGLE_API_KEY")
        defer {
            restore(previousDefault, forKey: "GOOGLE_API_KEY")
            restoreEnvironment(previousEnvironment, key: "GOOGLE_API_KEY")
        }

        defaults.set("test-api-key", forKey: "GOOGLE_API_KEY")

        #expect(Config.googleAPIKey == "test-api-key")
    }

    @Test("Stored key preview masks configured key")
    func storedKeyPreviewMasksKey() {
        let defaults = UserDefaults.standard
        let previousDefault = defaults.object(forKey: "GOOGLE_API_KEY")
        let previousEnvironment = getenv("GOOGLE_API_KEY").map { String(cString: $0) }
        unsetenv("GOOGLE_API_KEY")
        defer {
            restore(previousDefault, forKey: "GOOGLE_API_KEY")
            restoreEnvironment(previousEnvironment, key: "GOOGLE_API_KEY")
        }

        defaults.set("AIzaSyExampleKey1234567890", forKey: "GOOGLE_API_KEY")

        #expect(GeminiService.storedKeyPreview == "AIzaSy...7890")
    }

    @Test("Stored key preview is nil when no key is configured")
    func storedKeyPreviewNilWithoutKey() {
        let defaults = UserDefaults.standard
        let previousDefault = defaults.object(forKey: "GOOGLE_API_KEY")
        let previousEnvironment = getenv("GOOGLE_API_KEY").map { String(cString: $0) }

        defaults.removeObject(forKey: "GOOGLE_API_KEY")
        unsetenv("GOOGLE_API_KEY")
        defer {
            restore(previousDefault, forKey: "GOOGLE_API_KEY")
            restoreEnvironment(previousEnvironment, key: "GOOGLE_API_KEY")
        }

        #expect(GeminiService.storedKeyPreview == nil)
    }
}

private func restore(_ value: Any?, forKey key: String) {
    if let value {
        UserDefaults.standard.set(value, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private func restoreEnvironment(_ value: String?, key: String) {
    if let value {
        setenv(key, value, 1)
    } else {
        unsetenv(key)
    }
}
