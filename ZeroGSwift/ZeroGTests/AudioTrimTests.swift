import Foundation
import Testing
@testable import ZeroG

/// Tests for AudioRecorder.trimTrailingSilence — the pure tail-trimming pass.
/// At 16 kHz: window = 320 samples (20 ms), tail kept = 16_000 * 0.3 = 4_800 samples.
@Suite
struct AudioTrimTests {

    @Test("Empty input returns empty")
    func empty() {
        #expect(AudioRecorder.trimTrailingSilence([]).isEmpty)
    }

    @Test("Input shorter than one window is returned untouched")
    func shorterThanWindow() {
        let samples = [Float](repeating: 0.0, count: 100)
        #expect(AudioRecorder.trimTrailingSilence(samples).count == 100)
    }

    @Test("All-silence input is left alone (no speech ever detected)")
    func allSilence() {
        let samples = [Float](repeating: 0.0, count: 5_000)
        #expect(AudioRecorder.trimTrailingSilence(samples).count == 5_000)
    }

    @Test("Trailing silence beyond the kept tail is trimmed")
    func trimsTrailingSilence() {
        // 1_600 voiced samples (5 windows) then a long silent tail.
        var samples = [Float](repeating: 0.5, count: 1_600)
        samples += [Float](repeating: 0.0, count: 10_000)
        // lastVoicedEnd = 1_600; kept = 1_600 + 4_800 = 6_400.
        #expect(AudioRecorder.trimTrailingSilence(samples).count == 6_400)
    }

    @Test("Short trailing silence within the tail budget is preserved")
    func keepsShortTail() {
        // Voiced region, then a silent tail smaller than the 4_800-sample budget.
        var samples = [Float](repeating: 0.5, count: 1_600)
        samples += [Float](repeating: 0.0, count: 1_000)
        #expect(AudioRecorder.trimTrailingSilence(samples).count == 2_600)
    }
}
