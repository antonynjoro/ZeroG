import Foundation
import Testing
@testable import ZeroG

@Suite(.serialized)
struct ConfigTests {
    @Test("Config exposes expected audio and model defaults")
    func defaultConstants() {
        #expect(Config.silenceThreshold == 0.003)
        #expect(Config.silenceDuration == 12.0)
        #expect(Config.recordingTailDuration == 0.3)
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
