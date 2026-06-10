import SwiftUI
import Cocoa

// MARK: - ZeroG Application Entry Point

@main
struct ZeroGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    
    // MARK: Core Components
    
    private var stateMachine: AppStateMachine!
    private var transcriptionEngine: Transcribing!
    private var audioRecorder: AudioRecorder!
    private var keyMonitor: KeyMonitor!
    
    // MARK: GUI Components
    
    private var statusBarController: StatusBarController!
    private var hudController: HUDPanelController!

    /// SPIKE (spike/fluidaudio-parakeet): the most recent captured audio buffer, fed to the
    /// backend comparator so every engine sees identical audio.
    private var lastCapturedBuffer: [Float] = []

    // MARK: Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        Config.load()
        GeminiService.configure()
        
        // Initialize core
        stateMachine = AppStateMachine()
        transcriptionEngine = Self.makeTranscriptionEngine(for: Config.sttBackend)
        Log.debug("ZeroGApp", "STT backend: \(Config.sttBackend.rawValue)")

        audioRecorder = AudioRecorder(
            stateMachine: stateMachine,
            transcriptionEngine: transcriptionEngine
        )

        // SPIKE: remember the last buffer so the backend comparator can re-run it.
        audioRecorder.onCapturedAudio = { [weak self] buffer in
            self?.lastCapturedBuffer = buffer
        }
        
        keyMonitor = KeyMonitor(
            stateMachine: stateMachine,
            onStartRecording: { [weak self] in
                self?.audioRecorder.startRecording()
            },
            onStopRecording: { [weak self] in
                self?.audioRecorder.beginProcessing()
            }
        )
        
        // Initialize GUI
        statusBarController = StatusBarController(
            stateMachine: stateMachine,
            onRunBackendComparison: { [weak self] in self?.runBackendComparison() }
        )
        hudController = HUDPanelController(stateMachine: stateMachine)
        
        // Start key monitoring
        keyMonitor.start()
        
        // Show loading state and download model
        stateMachine.transition(to: .loading("Starting up..."))
        
        // Wire progress updates to the menu bar status
        transcriptionEngine.onStatusUpdate = { [weak self] message in
            self?.stateMachine.transition(to: .loading(message))
        }
        
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriptionEngine.initialize()
                
                DispatchQueue.main.async {
                    self.stateMachine.transition(to: .idle)
                    Log.debug("ZeroGApp", "🧑‍🚀 ZeroG Ready — Hold \(Config.triggerKey.displayName) to start recording")
                }
            } catch {
                Log.error("ZeroGApp", "⚠️ WhisperKit initialization failed: \(error)")
                DispatchQueue.main.async {
                    self.stateMachine.transition(to: .error("Model Failed"))
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        keyMonitor?.stop()
    }

    // MARK: - STT backend (FluidAudio spike)

    /// Build the live transcription engine for the selected backend. Only the chosen one is
    /// instantiated, so we never load Whisper and Parakeet models at the same time.
    private static func makeTranscriptionEngine(for backend: Config.STTBackend) -> Transcribing {
        switch backend {
        case .whisper:    return TranscriptionEngine()
        case .parakeetV2: return ParakeetTranscriptionEngine(variant: .v2)
        case .parakeetV3: return ParakeetTranscriptionEngine(variant: .v3)
        }
    }

    /// SPIKE: run the last captured recording through every backend and log the comparison.
    private func runBackendComparison() {
        let buffer = lastCapturedBuffer
        Task.detached {
            await BackendComparator.compare(buffer: buffer)
        }
    }
}
