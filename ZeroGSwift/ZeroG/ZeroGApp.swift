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
    private var transcriptionEngine: TranscriptionEngine!
    private var audioRecorder: AudioRecorder!
    private var keyMonitor: KeyMonitor!
    
    // MARK: GUI Components
    
    private var statusBarController: StatusBarController!
    private var hudController: HUDPanelController!
    
    // MARK: Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        Config.load()
        GeminiService.configure()
        
        // Initialize core
        stateMachine = AppStateMachine()
        transcriptionEngine = TranscriptionEngine()
        
        audioRecorder = AudioRecorder(
            stateMachine: stateMachine,
            transcriptionEngine: transcriptionEngine
        )
        
        keyMonitor = KeyMonitor(
            stateMachine: stateMachine,
            onStartRecording: { [weak self] in
                self?.audioRecorder.startRecording()
            },
            onStopRecording: { [weak self] useGemini in
                self?.audioRecorder.stopRecording(useGemini: useGemini)
            }
        )
        
        // Initialize GUI
        statusBarController = StatusBarController(stateMachine: stateMachine)
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
}
