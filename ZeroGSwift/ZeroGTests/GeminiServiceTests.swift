import Foundation
import Testing
@testable import ZeroG

@Suite(.serialized)
struct GeminiServiceTests {
    @Test("Stored key preview masks configured key")
    func storedKeyPreviewMasksKey() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "GOOGLE_API_KEY")
        defer { restore(previous, forKey: "GOOGLE_API_KEY") }

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
