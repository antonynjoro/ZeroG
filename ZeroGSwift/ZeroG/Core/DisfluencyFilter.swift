import Foundation

// MARK: - Disfluency Filter

/// Pure text-domain pass that strips spoken filler words ("um", "uh", …) from a transcript.
///
/// Parakeet transcribes verbatim by training (no model-side option exists), so cleanup
/// happens here — same decouple-by-domain principle as the old Whisper hallucination
/// cleanup: never fight it in the audio/model domain.
///
/// Deliberately bounded: operates token-by-token on exact, whole-word matches against a
/// fixed list. It can only ever *remove* a listed filler — it cannot misspell, reorder, or
/// invent text. Words that merely contain a filler ("umbrella", "mm-hmm") are untouched
/// because the comparison is against the token's full alphabetic core, not a substring.
enum DisfluencyFilter {

    /// Spoken fillers to remove. Standalone tokens only, matched case-insensitively after
    /// stripping surrounding punctuation. Conservative: every entry is essentially never a
    /// legitimate standalone word in dictated English.
    static let fillers: Set<String> = ["um", "uh", "uhm", "uhh", "umm", "ah", "er", "erm", "mm", "hmm"]

    /// Punctuation that may cling to a spoken-filler token ("Um,", "uh...").
    private static let clingingPunctuation = CharacterSet(charactersIn: ".,!?;:…")

    /// Remove standalone filler tokens, then repair the seams: collapse whitespace,
    /// restore the original terminal punctuation if the dropped tail carried it, and
    /// restore a leading capital if the dropped head carried it.
    static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let tokens = trimmed.split(separator: " ").map(String.init)

        // Walk tokens, dropping fillers. When a dropped filler opened a sentence (start of
        // text, or right after terminal punctuation) and carried the capital, hand that
        // capital to the next kept token so the sentence seam stays well-formed.
        var kept: [String] = []
        var capitalizeNext = false
        for (index, token) in tokens.enumerated() {
            if isFiller(token) {
                let openedSentence = index == 0
                    || tokens[index - 1].last.map { ".!?".contains($0) } == true
                if openedSentence, token.first?.isUppercase == true {
                    capitalizeNext = true
                }
                continue
            }
            var word = token
            if capitalizeNext, let first = word.first, first.isLowercase {
                word = first.uppercased() + word.dropFirst()
            }
            capitalizeNext = false
            kept.append(word)
        }

        // Everything was filler → empty transcript (nothing worth pasting).
        guard !kept.isEmpty else { return "" }
        // Nothing dropped → return the input untouched.
        guard kept.count != tokens.count else { return trimmed }

        var result = kept.joined(separator: " ")

        // Final seam: if the original ended in terminal punctuation but the cleaned text
        // lost it (e.g. "fine, um." → "fine,"), swap any dangling comma-class punctuation
        // for the original terminal mark.
        if let terminal = trimmed.last, ".!?".contains(terminal), result.last != terminal {
            while let last = result.last, ",;:".contains(last) {
                result.removeLast()
            }
            if let last = result.last, !".!?".contains(last) {
                result.append(terminal)
            }
        }

        return result
    }

    /// True when the token is a filler once surrounding punctuation is stripped.
    /// Whole-token match only — hyphenated or compound tokens ("mm-hmm") never match.
    private static func isFiller(_ token: String) -> Bool {
        let core = token
            .trimmingCharacters(in: clingingPunctuation)
            .lowercased()
        return fillers.contains(core)
    }
}
