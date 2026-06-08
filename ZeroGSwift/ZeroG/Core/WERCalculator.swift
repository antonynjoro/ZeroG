import Foundation

// MARK: - WERCalculator

/// Pure, dependency-free Word Error Rate scorer for the FluidAudio/Parakeet spike.
///
/// WER = (word-level edit distance between reference and hypothesis) / (reference word count).
/// Both strings are lowercased and split on whitespace; matching is exact per word (no
/// stemming, no punctuation stripping beyond what whitespace-splitting gives). Good enough
/// for relative A/B comparison of two STT backends on the same reference.
///
/// No audio, no I/O, no external deps — trivially unit-testable.
/// See docs/spikes/fluidaudio-parakeet-spike.md.
enum WERCalculator {

    /// Word Error Rate of `hypothesis` against the ground-truth `reference`.
    /// - Returns: 0.0 for a perfect match. If the reference is empty, returns 0.0 when the
    ///   hypothesis is also empty, else 1.0 (every hypothesis word is an insertion error).
    static func wer(reference: String, hypothesis: String) -> Double {
        let ref = tokenize(reference)
        let hyp = tokenize(hypothesis)

        guard !ref.isEmpty else { return hyp.isEmpty ? 0.0 : 1.0 }

        let distance = editDistance(ref, hyp)
        return Double(distance) / Double(ref.count)
    }

    /// Lowercase and split on any whitespace/newlines, dropping empty tokens.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// Classic Levenshtein edit distance over two word arrays, two-row DP (O(min) memory).
    private static func editDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + cost  // substitution / match
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
