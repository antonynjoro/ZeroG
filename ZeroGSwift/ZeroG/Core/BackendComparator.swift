import Foundation

// MARK: - Backend Comparator (FluidAudio spike)

/// Runs the SAME captured audio buffer through every STT backend and reports raw transcript,
/// cold latency (first transcribe), and warm-median latency — the objective A/B data the
/// FluidAudio/Parakeet spike exists to gather. SPIKE ONLY (`spike/fluidaudio-parakeet`).
///
/// Loads ONE backend at a time (initialize → transcribe → `unloadModel`) so the ~2 GB Whisper
/// model and the ~66 MB Parakeet models are never resident together. Results go to `Log.debug`
/// and are appended to `~/zerog-backend-comparison.log` for easy copy into the spike doc.
///
/// If a non-empty `reference` is supplied, WER is computed via `WERCalculator`; otherwise the
/// transcript is logged for manual comparison.
enum BackendComparator {

    /// Backends to compare, in order. Each is built fresh so model loading is measured too.
    private static func makeEngines() -> [(name: String, engine: Transcribing)] {
        [
            ("whisper", TranscriptionEngine()),
            ("parakeetV2", ParakeetTranscriptionEngine(variant: .v2)),
            ("parakeetV3", ParakeetTranscriptionEngine(variant: .v3)),
        ]
    }

    /// Compare all backends on `buffer`. `warmRuns` extra timed runs follow the cold run.
    /// Runs sequentially and unloads each engine before the next to bound memory.
    static func compare(buffer: [Float], reference: String? = nil, warmRuns: Int = 3) async {
        guard !buffer.isEmpty else {
            Log.error("Comparator", "No captured audio yet — record once, then run the comparison.")
            return
        }

        let audioSeconds = Double(buffer.count) / AudioConstants.sampleRate
        log("===== STT backend comparison =====")
        log(String(format: "audio: %.1fs (%d samples @ %.0f Hz), warmRuns: %d",
                   audioSeconds, buffer.count, AudioConstants.sampleRate, warmRuns))
        if let reference, !reference.isEmpty {
            log("reference: \"\(reference)\"")
        } else {
            log("reference: (none — transcripts logged for manual WER)")
        }

        for (name, engine) in makeEngines() {
            await runOne(name: name, engine: engine, buffer: buffer,
                         reference: reference, warmRuns: warmRuns)
        }
        log("===== end comparison =====")
    }

    // MARK: - Private

    private static func runOne(name: String, engine: Transcribing, buffer: [Float],
                               reference: String?, warmRuns: Int) async {
        do {
            // Cold: model load + first transcription.
            let loadStart = CFAbsoluteTimeGetCurrent()
            try await engine.initialize()
            let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000

            let coldStart = CFAbsoluteTimeGetCurrent()
            let transcript = try await engine.transcribe(buffer)
            let coldMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000

            // Warm: median of N subsequent runs.
            var warmTimes: [Double] = []
            for _ in 0..<max(0, warmRuns) {
                let t = CFAbsoluteTimeGetCurrent()
                _ = try await engine.transcribe(buffer)
                warmTimes.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            }
            let warmMedian = median(warmTimes)

            var line = String(format: "[%@] load=%.0fms cold=%.0fms warmMedian=%@",
                              name, loadMs, coldMs, warmMedian.map { String(format: "%.0fms", $0) } ?? "n/a")
            if let reference, !reference.isEmpty {
                let wer = WERCalculator.wer(reference: reference, hypothesis: transcript)
                line += String(format: " WER=%.1f%%", wer * 100)
            }
            log(line)
            log("[\(name)] transcript: \"\(transcript)\"")
        } catch {
            log("[\(name)] FAILED: \(error.localizedDescription)")
        }

        // Free this backend's model before loading the next (bound peak memory).
        engine.unloadModel()
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Log to the debug console and append to a home-directory file for easy copy-out.
    private static func log(_ message: String) {
        Log.debug("Comparator", message)
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("zerog-backend-comparison.log")
        let line = message + "\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
