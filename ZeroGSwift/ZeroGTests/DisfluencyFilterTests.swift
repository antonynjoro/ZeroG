import Foundation
import Testing
@testable import ZeroG

/// Tests for DisfluencyFilter — the bounded text-domain filler stripper applied to
/// Parakeet output (Parakeet transcribes verbatim; Whisper self-cleans).
@Suite
struct DisfluencyFilterTests {

    @Test("Clean text passes through untouched")
    func cleanTextUntouched() {
        let text = "The quick brown fox jumps over the lazy dog."
        #expect(DisfluencyFilter.clean(text) == text)
    }

    @Test("Mid-sentence filler with clinging comma is removed")
    func midSentenceFiller() {
        #expect(DisfluencyFilter.clean("and, um, that's probably fine")
                == "and, that's probably fine")
    }

    @Test("Leading filler is removed and the capital restored")
    func leadingFillerRecapitalizes() {
        #expect(DisfluencyFilter.clean("Um, so that's one thing to keep in mind.")
                == "So that's one thing to keep in mind.")
    }

    @Test("Trailing filler keeps the sentence's terminal period")
    func trailingFillerKeepsPeriod() {
        #expect(DisfluencyFilter.clean("I think that's fine, um.")
                == "I think that's fine.")
    }

    @Test("Multiple fillers in one utterance are all removed")
    func multipleFillers() {
        #expect(DisfluencyFilter.clean("So, um, I wonder, uh, whether we can, uhm, use it.")
                == "So, I wonder, whether we can, use it.")
    }

    @Test("Words containing fillers are untouched (umbrella, ah-ha, mm-hmm)")
    func containingWordsUntouched() {
        let text = "My umbrella made an ah-ha moment, mm-hmm."
        #expect(DisfluencyFilter.clean(text) == text)
    }

    @Test("Case-insensitive: capitalized and uppercase fillers match")
    func caseInsensitive() {
        #expect(DisfluencyFilter.clean("Uh, right. UM, sure.") == "Right. Sure.")
    }

    @Test("All-filler input collapses to empty")
    func allFillerEmpty() {
        #expect(DisfluencyFilter.clean("Um, uh, hmm.") == "")
    }

    @Test("Empty and whitespace-only input returns empty")
    func emptyInput() {
        #expect(DisfluencyFilter.clean("") == "")
        #expect(DisfluencyFilter.clean("   ") == "")
    }

    @Test("Question mark terminal punctuation is preserved across a trailing filler")
    func questionMarkPreserved() {
        #expect(DisfluencyFilter.clean("How likely is it to hallucinate, um?")
                == "How likely is it to hallucinate?")
    }

    @Test("Lowercase original start stays lowercase after a leading filler drop")
    func lowercaseStartStaysLowercase() {
        #expect(DisfluencyFilter.clean("um so we keep going")
                == "so we keep going")
    }
}
