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

    // MARK: Permissions / Onboarding

    private var permissionsManager: PermissionsManager!
    private var onboardingController: OnboardingWindowController!

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

        keyMonitor = KeyMonitor(
            stateMachine: stateMachine,
            onStartRecording: { [weak self] in
                guard let self else { return }
                // The hotkey fired, but the Mic grant may still be missing — in
                // that case open the wizard instead of starting a recording that
                // can't complete.
                self.permissionsManager.refresh()
                if self.permissionsManager.allGranted {
                    self.audioRecorder.startRecording()
                } else {
                    // KeyMonitor already flipped the state to .recording before
                    // this callback — undo it, or the HUD sticks on "RECORDING…"
                    // with no recording running.
                    self.stateMachine.transition(to: .idle)
                    self.onboardingController.show()
                }
            },
            onStopRecording: { [weak self] in
                self?.audioRecorder.beginProcessing()
            }
        )
        
        // Permissions + onboarding wizard
        permissionsManager = PermissionsManager()
        onboardingController = OnboardingWindowController(permissions: permissionsManager)
        // Bring the key tap up after an Accessibility grant: tear down any existing
        // tap and install a fresh one, reporting whether it came up. This is NOT a
        // permission check — tapCreate can succeed with events withheld — it only
        // ensures the hotkey is wired through the freshly-granted trust.
        onboardingController.attemptKeyTap = { [weak self] in
            guard let self else { return false }
            self.keyMonitor.stop()
            return self.keyMonitor.start()
        }
        // The wizard switches the app to .regular for a Dock icon; reverting to
        // .accessory on close leaves the event tap dead. Rebuild it once the
        // policy has settled so the hotkey survives closing onboarding without a
        // relaunch.
        onboardingController.onClose = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.permissionsManager.refresh()
                if self.permissionsManager.status(for: .accessibility) == .granted {
                    self.keyMonitor.stop()
                    self.keyMonitor.start()
                }
                self.statusBarController.updateHotkeyStatus(
                    hotkeyLive: self.keyMonitor.isRunning)
            }
        }
        permissionsManager.onPermissionGranted = { [weak self] kind in
            guard let self else { return }
            self.onboardingController.handlePermissionGranted(kind)
            self.statusBarController.updateHotkeyStatus(hotkeyLive: self.keyMonitor.isRunning)
        }

        // Initialize GUI
        statusBarController = StatusBarController(
            stateMachine: stateMachine,
            onShowPermissions: { [weak self] in self?.onboardingController.show() }
        )
        hudController = HUDPanelController(stateMachine: stateMachine)

        // Re-open the wizard whenever an action is blocked by a missing permission
        // (e.g. paste blocked by Accessibility — posted from the inject path).
        NotificationCenter.default.addObserver(
            forName: .permissionsNeeded, object: nil, queue: .main
        ) { [weak self] _ in
            self?.onboardingController.show()
        }

        // Permission-gated startup. Read live status, log it, and only install the
        // key tap if Accessibility is granted (it authorizes the listen-only tap);
        // surface the wizard if anything is missing. Model download below runs
        // concurrently regardless.
        permissionsManager.refresh()
        logPermissionStatuses()

        if permissionsManager.status(for: .accessibility) == .granted {
            keyMonitor.start()
        }
        statusBarController.updateHotkeyStatus(hotkeyLive: keyMonitor.isRunning)

        if permissionsManager.shouldShowOnboarding {
            onboardingController.show()
        }

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

    /// Log the live permission status for each kind — visible in Console so a
    /// "wizard didn't appear" report can be diagnosed without reading TCC.db.
    private func logPermissionStatuses() {
        for kind in PermissionKind.allCases {
            Log.error("Permissions", "\(kind.displayName): \(permissionsManager.status(for: kind))")
        }
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
}
