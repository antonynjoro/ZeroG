import Foundation
import Testing
@testable import ZeroG

@Suite
struct TranscriptionEngineTests {

    // Guard against re-introducing withoutTimestamps or zeroing the fallback count —
    // both caused long-sentence truncation (Whisper lost temporal position mid-decode).
    @Test("fastDecodingOptions has timestamp and fallback settings required for long-sentence accuracy")
    func decodingOptionsPreventTruncation() {
        let opts = TranscriptionEngine.fastDecodingOptions
        #expect(opts.withoutTimestamps == false,
            "withoutTimestamps must be false — true causes Whisper to lose position in audio >~10s and stop early")
        #expect(opts.temperatureFallbackCount >= 1,
            "temperatureFallbackCount must be ≥1 so a failed first-pass decode can retry")
    }

    @Test("fastDecodingOptions uses VAD chunking and correct task/language")
    func decodingOptionsBaselineConfig() {
        let opts = TranscriptionEngine.fastDecodingOptions
        #expect(opts.task == .transcribe)
        #expect(opts.language == "en")
        #expect(opts.skipSpecialTokens == true)
        #expect(opts.chunkingStrategy == .vad)
        #expect(opts.detectLanguage == false)
    }
}
