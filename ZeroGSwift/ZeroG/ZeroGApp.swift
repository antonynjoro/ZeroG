import SwiftUI
import Cocoa

// MARK: - ZeroG Application Entry Point

/// Native Swift replacement for `main.py` + `app.py`.
/// Uses SwiftUI App lifecycle with `@NSApplicationDelegateAdaptor` for AppKit integration.
@main
struct ZeroGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No visible window — the app is status-bar only with a floating HUD
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

/// Coordinates initialization of all subsystems.
/// Replaces `ZeroGApp(NSObject)` from the Python pyobjc version.
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: Core Components
    
    /// All components initialized lazily in applicationDidFinishLaunching
    /// to avoid actor-isolation issues with stored property default initializers.
    private var stateMachine: AppStateMachine!
    private var transcriptionEngine: TranscriptionEngine!
    private var audioRecorder: AudioRecorder!
    private var keyMonitor: KeyMonitor!
    
    // MARK: GUI Components
    
    private var statusBarController: StatusBarController!
    private var hudController: HUDPanelController!
    
    // MARK: Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — we're a menu-bar-only app
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize configuration
        Config.load()
        
        // Initialize Gemini (if API key is available)
        GeminiService.configure()
        
        // Initialize core components
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
        
        // Load WhisperKit model in background
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.transcriptionEngine.initialize()
                print("🧑‍🚀 ZeroG Ready (Native Swift Mode)")
            } catch {
                print("⚠️ WhisperKit initialization failed: \(error)")
                DispatchQueue.main.async {
                    self.stateMachine.transition(to: .error("Model Load Failed"))
                    self.stateMachine.resetToIdle(after: 5.0)
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        keyMonitor?.stop()
    }
}
