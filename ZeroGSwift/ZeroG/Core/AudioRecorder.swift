import Foundation
import AVFoundation
import AppKit
import Combine
import Accelerate

// MARK: - Constants

/// Audio capture constants. Sample-rate truth lives here — other components
/// (e.g. `TranscriptionEngine`) reference `AudioConstants.sampleRate` rather than
/// re-hardcoding 16_000.
enum AudioConstants {
    static let sampleRate: Double = 16_000
    static let chunkMinDuration: TimeInterval = 15.0
    static let chunkMaxDuration: TimeInterval = 25.0
    static let bufferSize: AVAudioFrameCount = 4096
}

// MARK: - Audio Recorder

/// Captures audio using AVAudioEngine with real-time level metering and safety-only silence detection.
/// Replaces Python's `sounddevice` / PortAudio integration, eliminating deadlock-prone C library bindings.
///
/// ## Architecture
/// - Installs a tap on the audio engine's input node
/// - Accumulates audio samples into chunks
/// - Detects prolonged true silence as a safety cutoff
/// - Publishes audio level for HUD visualization via the state machine
final class AudioRecorder: @unchecked Sendable {
    
    // MARK: Dependencies
    
    private let stateMachine: AppStateMachine
    private let transcriptionEngine: Transcribing
    
    // MARK: Audio Engine
    
    private let audioEngine = AVAudioEngine()
    private var isRecording = false
    
    // MARK: Audio Accumulation
    
    /// Thread-safe buffer for accumulated audio samples during a recording session.
    private var accumulatedSamples: [Float] = []
    private let sampleQueue = DispatchQueue(label: "com.zerog.audioSamples", qos: .userInteractive)
    
    /// Chunks of audio ready for transcription, produced by the background chunker.
    private var transcribedTexts: [String] = []
    
    // MARK: Safety Silence Detection

    /// Pure auto-stop decision logic (thresholds tested in isolation).
    private var silenceTracker = SilenceTracker(
        rmsThreshold: Config.silenceThreshold,
        silenceDuration: Config.silenceDuration
    )
    
    // MARK: Lifecycle
    
    init(stateMachine: AppStateMachine, transcriptionEngine: Transcribing) {
        self.stateMachine = stateMachine
        self.transcriptionEngine = transcriptionEngine
    }
    
    // MARK: - Recording Control
    
    /// Begin capturing audio from the default input device.
    func startRecording() {
        guard !isRecording else { return }
        
        // Reset state
        silenceTracker.reset()
        sampleQueue.sync {
            accumulatedSamples.removeAll(keepingCapacity: true)
        }
        transcribedTexts.removeAll()
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)
        
        // Ensure we have a valid format
        guard recordingFormat.sampleRate > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine.transition(to: .error("No microphone available"))
                self?.stateMachine.resetToIdle(after: Config.Timing.errorReset)
            }
            return
        }
        
        // Install tap on the input node for raw audio capture
        inputNode.installTap(onBus: 0, bufferSize: AudioConstants.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, format: recordingFormat)
        }
        
        do {
            try audioEngine.start()
            isRecording = true
            playFeedbackSound()

            Log.debug("AudioRecorder", "Recording started. Format: \(recordingFormat)")
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine.transition(to: .error("Mic Error: \(error.localizedDescription)"))
                self?.stateMachine.resetToIdle(after: Config.Timing.errorReset)
            }
        }
    }
    
    /// The single entry point for ending a recording session. Every stop trigger
    /// — key release, safety timeout, mid-session trigger-key change, and the
    /// silence cutoff — routes here so the "are we recording? → transition →
    /// stop" sequence lives in exactly one place. Reads the Gemini flag from the
    /// session context. Must be called on the main thread (it touches the state
    /// machine).
    func beginProcessing() {
        guard stateMachine.currentState == .recording else { return }
        let useGemini = stateMachine.useGemini
        stateMachine.transition(to: .processing)
        stopRecording(useGemini: useGemini)
    }

    /// Stop capturing audio and trigger transcription of accumulated samples.
    /// Continues recording for a short tail period after key release to capture trailing speech.
    func stopRecording(useGemini: Bool) {
        guard isRecording else { return }
        isRecording = false

        Log.debug("AudioRecorder", "Recording stopping (tail \(Config.recordingTailDuration)s). useGemini=\(useGemini)")

        DispatchQueue.main.asyncAfter(deadline: .now() + Config.recordingTailDuration) { [weak self] in
            guard let self else { return }
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine.stop()

            let rawAudio: [Float] = self.sampleQueue.sync { self.accumulatedSamples }
            let audioData = Self.trimTrailingSilence(rawAudio)

            Task.detached { [weak self] in
                await self?.transcribeAndInject(audioData: audioData, useGemini: useGemini)
            }
        }
    }

    /// Drop trailing samples whose 20 ms-window RMS falls below the silence threshold,
    /// keeping a small tail so the model gets a clean end-of-utterance.
    /// internal so tests can drive it directly.
    static func trimTrailingSilence(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let sampleRate = Int(AudioConstants.sampleRate)
        let windowSize = sampleRate / 50      // 20 ms windows = 320 samples @ 16 kHz
        // Keep trailing silence so the decoder finalizes the last word; the post-decode
        // cleanup pass absorbs any silence that turns into a hallucination.
        let tailKeep = Int(Double(sampleRate) * Config.TranscriptionQuality.trailingTailSeconds)
        guard samples.count > windowSize else { return samples }

        var lastVoicedEnd = 0
        var idx = 0
        while idx + windowSize <= samples.count {
            var sumSq: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_svesq(ptr.baseAddress! + idx, 1, &sumSq, vDSP_Length(windowSize))
            }
            let rms = sqrt(sumSq / Float(windowSize))
            if rms >= Config.silenceThreshold {
                lastVoicedEnd = idx + windowSize
            }
            idx += windowSize
        }

        if lastVoicedEnd == 0 { return samples }   // never detected speech — leave it alone
        let endIdx = min(samples.count, lastVoicedEnd + tailKeep)
        return Array(samples[0..<endIdx])
    }
    
    // MARK: - Audio Processing
    
    /// Process an incoming audio buffer: compute RMS, detect silence, accumulate samples.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        
        // Convert to 16kHz mono if needed
        let samples: [Float]
        if format.sampleRate != AudioConstants.sampleRate {
            // Box-filter downsample with vDSP_desamp (averages each window of `step` samples).
            let ratio = format.sampleRate / AudioConstants.sampleRate
            let step = max(1, Int(ratio.rounded()))
            let outCount = frameLength / step
            if outCount > 0 {
                var filter = [Float](repeating: 1.0 / Float(step), count: step)
                var output = [Float](repeating: 0, count: outCount)
                vDSP_desamp(channelData, vDSP_Stride(step), &filter, &output, vDSP_Length(outCount), vDSP_Length(step))
                samples = output
            } else {
                samples = []
            }
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        }

        // Compute RMS for level metering (vectorized).
        var rms: Float = 0
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer { ptr in
                vDSP_rmsqv(ptr.baseAddress!, 1, &rms, vDSP_Length(samples.count))
            }
        }
        let normalizedLevel = min(1.0, rms * 10.0)
        
        // Publish audio level to HUD (dispatch to main thread)
        DispatchQueue.main.async { [weak self] in
            self?.stateMachine.audioLevel = normalizedLevel
        }
        
        // Accumulate samples
        sampleQueue.async { [weak self] in
            self?.accumulatedSamples.append(contentsOf: samples)
        }
        
        // Safety-only silence detection. Normal recording still ends when Control is released.
        if silenceTracker.observe(rms: rms, at: Date()) == .stop {
            Log.debug("AudioRecorder", "Safety silence detected (>\(Config.silenceDuration)s). Auto-stopping.")
            DispatchQueue.main.async { [weak self] in
                self?.beginProcessing()
            }
        }
    }
    
    // MARK: - Transcription Pipeline
    
    /// Transcribe audio data using WhisperKit and inject the result.
    private func transcribeAndInject(audioData: [Float], useGemini: Bool) async {
        guard !audioData.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine.transition(to: .idle)
            }
            return
        }
        
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Transcribe
            let text = try await transcriptionEngine.transcribe(audioData)
            
            let transcriptionDuration = CFAbsoluteTimeGetCurrent() - startTime
            
            let audioDuration = Double(audioData.count) / AudioConstants.sampleRate
            Log.debug("AudioRecorder", "Transcribed \(String(format: "%.1f", audioDuration))s audio in \(String(format: "%.2f", transcriptionDuration))s: \(text)")
            
            guard !text.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.stateMachine.transition(to: .idle)
                }
                return
            }
            
            // Optional Gemini processing
            var finalText = text
            if useGemini {
                finalText = await GeminiService.shared?.process(text) ?? text
            }
            
            // Store for "Copy Last Transcription" menu item
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine.lastTranscription = finalText
            }

            // Inject text
            TextInjector.injectText(finalText)
            
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine.transition(to: .success)
                self?.stateMachine.resetToIdle()
            }
            
        } catch {
            Log.debug("AudioRecorder", "Transcription error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.stateMachine.transition(to: .error("Processing Failed"))
                self?.stateMachine.resetToIdle(after: Config.Timing.errorReset)
            }
        }
    }
    
    // MARK: - Sound Feedback
    
    /// Play the system "Pop" sound as recording feedback.
    private func playFeedbackSound() {
        NSSound(named: "Pop")?.play()
    }
}
