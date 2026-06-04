import Foundation
import Testing
import WhisperKit
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

    @Test("fastDecodingOptions disables chunking and uses correct task/language")
    func decodingOptionsBaselineConfig() {
        let opts = TranscriptionEngine.fastDecodingOptions
        #expect(opts.task == .transcribe)
        #expect(opts.language == "en")
        #expect(opts.skipSpecialTokens == true)
        // Decision: VAD chunking removed entirely. It only ever activated above one 30s
        // window and gave long recordings isolated chunks prone to truncation/hallucination.
        #expect(opts.chunkingStrategy == ChunkingStrategy.none)
        #expect(opts.detectLanguage == false)
    }

    // MARK: - cleanTranscript

    private func seg(_ text: String, noSpeech: Float = 0.05, logProb: Float = -0.3)
        -> TranscriptionEngine.DecodedSegment {
        TranscriptionEngine.DecodedSegment(text: text, noSpeechProb: noSpeech, avgLogprob: logProb)
    }

    @Test("trailing segment with high noSpeechProb is dropped (primary signal, any words)")
    func dropsHighNoSpeechTail() {
        // Non-caption-ism phrase, so this isolates the noSpeechProb gate from the blocklist.
        let out = TranscriptionEngine.cleanTranscript([
            seg("Send the report today."),
            seg(" Over and out.", noSpeech: 0.92)
        ])
        #expect(out == "Send the report today.")
    }

    @Test("trailing real-speech segment with low noSpeechProb is preserved")
    func preservesSpokenTail() {
        // Low noSpeech + not blocklisted → genuine speech, kept verbatim.
        let out = TranscriptionEngine.cleanTranscript([
            seg("Here is the summary."),
            seg(" Let me know.", noSpeech: 0.04)
        ])
        // Cleanup re-joins split words, so internal whitespace is normalized to single spaces.
        #expect(out == "Here is the summary. Let me know.")
    }

    @Test("lone trailing 'thank you' is stripped by the backstop (accepted tradeoff)")
    func stripsLoneCaptionism() {
        // Even at low noSpeechProb, a standalone trailing caption-ism is dropped — the
        // user accepted this small risk of eating a genuinely-spoken one-word ending.
        let out = TranscriptionEngine.cleanTranscript([
            seg("Here is the summary."),
            seg(" Thank you.", noSpeech: 0.04)
        ])
        #expect(out == "Here is the summary.")
    }

    @Test("repeated phrase run is collapsed to one")
    func collapsesRepetition() {
        let out = TranscriptionEngine.cleanTranscript([
            seg("thank you thank you thank you", noSpeech: 0.04)
        ])
        // High-confidence segment survives the noSpeech gate, but the repetition collapses
        // to a single "thank you", which the backstop then strips as a lone caption-ism.
        #expect(out == "")
    }

    @Test("mid-utterance 'thank you' is left untouched")
    func preservesMidUtterance() {
        let out = TranscriptionEngine.cleanTranscript([
            seg("thank you for the report, send it today", noSpeech: 0.05)
        ])
        #expect(out == "thank you for the report, send it today")
    }

    @Test("genuine short repetition stays natural")
    func keepsNaturalRepetition() {
        // "no no no" is only 3 single-word reps — collapses to one "no", which is acceptable
        // and not a hallucination. The rest of the sentence is untouched.
        let out = TranscriptionEngine.collapseRepetitions("no no no that's wrong")
        #expect(out == "no that's wrong")
    }

    @Test("two reps are NOT collapsed (below threshold)")
    func twoRepsKept() {
        #expect(TranscriptionEngine.collapseRepetitions("really really good") == "really really good")
    }

    @Test("empty / all-silence input yields empty string")
    func emptyInput() {
        #expect(TranscriptionEngine.cleanTranscript([]) == "")
        #expect(TranscriptionEngine.cleanTranscript([seg("you", noSpeech: 0.95)]) == "")
    }
}
