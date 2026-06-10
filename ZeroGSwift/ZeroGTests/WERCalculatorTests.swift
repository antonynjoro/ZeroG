import Foundation
import Testing
@testable import ZeroG

/// Tests for WERCalculator — the pure word-level edit-distance scorer used by the
/// FluidAudio/Parakeet spike to objectively compare backends.
@Suite
struct WERCalculatorTests {

    @Test("Identical strings score 0.0")
    func perfectMatch() {
        #expect(WERCalculator.wer(reference: "hello world", hypothesis: "hello world") == 0.0)
    }

    @Test("Case and surrounding whitespace are ignored")
    func caseAndWhitespaceInsensitive() {
        #expect(WERCalculator.wer(reference: "Hello  World", hypothesis: "  hello world ") == 0.0)
    }

    @Test("One substitution in four words is 0.25")
    func oneSubstitution() {
        // "the quick brown fox" vs "the quick green fox" → 1 sub / 4 ref words
        #expect(WERCalculator.wer(reference: "the quick brown fox",
                                  hypothesis: "the quick green fox") == 0.25)
    }

    @Test("One deletion in four words is 0.25")
    func oneDeletion() {
        #expect(WERCalculator.wer(reference: "the quick brown fox",
                                  hypothesis: "the quick fox") == 0.25)
    }

    @Test("One insertion in two words is 0.5")
    func oneInsertion() {
        #expect(WERCalculator.wer(reference: "hello world",
                                  hypothesis: "hello there world") == 0.5)
    }

    @Test("Empty reference with empty hypothesis is 0.0")
    func bothEmpty() {
        #expect(WERCalculator.wer(reference: "", hypothesis: "") == 0.0)
    }

    @Test("Empty reference with non-empty hypothesis is 1.0")
    func emptyReferenceNonEmptyHypothesis() {
        #expect(WERCalculator.wer(reference: "", hypothesis: "spurious words") == 1.0)
    }

    @Test("Completely wrong hypothesis of equal length is 1.0")
    func allWrong() {
        #expect(WERCalculator.wer(reference: "alpha beta", hypothesis: "gamma delta") == 1.0)
    }

    @Test("Empty hypothesis against N reference words is 1.0 (all deletions)")
    func emptyHypothesis() {
        #expect(WERCalculator.wer(reference: "one two three", hypothesis: "") == 1.0)
    }

    @Test("tokenize splits on any whitespace and drops empties")
    func tokenization() {
        #expect(WERCalculator.tokenize("  a\tb\nc  ") == ["a", "b", "c"])
    }
}
