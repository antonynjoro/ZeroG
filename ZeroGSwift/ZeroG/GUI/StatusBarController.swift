import Cocoa
import Combine

// MARK: - Status Bar Controller

/// Manages the macOS status bar (menu bar) icon, dropdown menu, and status text.
final class StatusBarController {
    
    // MARK: Properties
    
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var copyTranscriptionMenuItem: NSMenuItem!
    private var geminiMenuItem: NSMenuItem!
    private var triggerKeySubmenu: NSMenu!
    private var backendSubmenu: NSMenu!
    private var cancellables = Set<AnyCancellable>()

    // MARK: Dependencies

    private let stateMachine: AppStateMachine

    /// SPIKE (spike/fluidaudio-parakeet): invoked by the "Compare STT backends" menu item.
    private let onRunBackendComparison: () -> Void

    // MARK: Initialization

    init(stateMachine: AppStateMachine, onRunBackendComparison: @escaping () -> Void = {}) {
        self.stateMachine = stateMachine
        self.onRunBackendComparison = onRunBackendComparison

        setupStatusItem()
        observeState()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let menu = NSMenu()
        
        // Status text (non-clickable)
        statusMenuItem = NSMenuItem(title: "Starting up...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Gemini API key
        let geminiTitle = geminiMenuTitle()
        geminiMenuItem = NSMenuItem(
            title: geminiTitle,
            action: #selector(showGeminiKeyDialog),
            keyEquivalent: ""
        )
        geminiMenuItem.target = self
        menu.addItem(geminiMenuItem)
        
        menu.addItem(NSMenuItem.separator())

        // Record Key submenu
        let triggerKeyItem = NSMenuItem(title: "Record Key", action: nil, keyEquivalent: "")
        triggerKeySubmenu = NSMenu()
        let currentKey = Config.triggerKey
        for option in TriggerKey.allOptions {
            let item = NSMenuItem(title: option.displayName, action: #selector(triggerKeySelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.id
            item.state = (option == currentKey) ? .on : .off
            triggerKeySubmenu.addItem(item)
        }
        triggerKeyItem.submenu = triggerKeySubmenu
        menu.addItem(triggerKeyItem)

        menu.addItem(NSMenuItem.separator())

        // SPIKE (spike/fluidaudio-parakeet): STT backend selector + comparison runner.
        let backendItem = NSMenuItem(title: "STT Backend (spike)", action: nil, keyEquivalent: "")
        backendSubmenu = NSMenu()
        let currentBackend = Config.sttBackend
        let backends: [(Config.STTBackend, String)] = [
            (.whisper, "WhisperKit (default)"),
            (.parakeetV2, "Parakeet v2 (English)"),
            (.parakeetV3, "Parakeet v3 (multilingual)"),
        ]
        for (backend, title) in backends {
            let item = NSMenuItem(title: title, action: #selector(backendSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = backend.rawValue
            item.state = (backend == currentBackend) ? .on : .off
            backendSubmenu.addItem(item)
        }
        backendItem.submenu = backendSubmenu
        menu.addItem(backendItem)

        let compareItem = NSMenuItem(
            title: "Compare STT Backends (last recording)",
            action: #selector(runBackendComparison),
            keyEquivalent: ""
        )
        compareItem.target = self
        menu.addItem(compareItem)

        menu.addItem(NSMenuItem.separator())

        // Copy Last Transcription
        copyTranscriptionMenuItem = NSMenuItem(
            title: "Copy Last Transcription",
            action: #selector(copyLastTranscription),
            keyEquivalent: ""
        )
        copyTranscriptionMenuItem.target = self
        copyTranscriptionMenuItem.isEnabled = false
        menu.addItem(copyTranscriptionMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit ZeroG",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateUI(for: .loading("Starting up..."))
    }
    
    // MARK: - State Observation
    
    private func observeState() {
        stateMachine.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateUI(for: state)
            }
            .store(in: &cancellables)
        
        stateMachine.$lastTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.copyTranscriptionMenuItem.isEnabled = (text != nil)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - UI Updates
    
    private func updateUI(for state: AppState) {
        guard let button = statusItem.button else { return }
        
        statusMenuItem.title = state.statusText

        // Menu symbol comes from the single state-presentation source of truth.
        // The symbol is independent of Gemini mode, so the flag is irrelevant here.
        let symbolName = state.presentation(useGemini: false).menuSymbol

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ZeroG Status") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configuredImage = (image.withSymbolConfiguration(config) ?? image).copy() as! NSImage
            configuredImage.isTemplate = true
            button.contentTintColor = nil
            button.image = configuredImage
        }
    }
    
    // MARK: - Trigger Key Selection

    @objc private func triggerKeySelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let newKey = TriggerKey.from(id: id)
        Config.setTriggerKey(newKey)

        for item in triggerKeySubmenu.items {
            item.state = (item.representedObject as? String) == id ? .on : .off
        }
    }

    // MARK: - STT Backend Selection (spike)

    @objc private func backendSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let backend = Config.STTBackend(rawValue: raw) else { return }
        Config.setSTTBackend(backend)

        for item in backendSubmenu.items {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }

        // The live engine is built once at launch, so a switch needs a relaunch to take effect.
        let alert = NSAlert()
        alert.messageText = "Backend set to \(backend.rawValue)"
        alert.informativeText = "Quit and relaunch ZeroG for the new backend to take effect.\n\n(The \"Compare STT Backends\" item runs all backends on your last recording without relaunching.)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func runBackendComparison() {
        onRunBackendComparison()
    }

    // MARK: - Gemini Key Dialog
    
    private func geminiMenuTitle() -> String {
        if let preview = GeminiService.storedKeyPreview {
            return "Gemini API Key: \(preview)"
        }
        return "Set Gemini API Key..."
    }
    
    @objc private func showGeminiKeyDialog() {
        // Bring app to front for the dialog
        NSApp.activate(ignoringOtherApps: true)
        
        let alert = NSAlert()
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Enter your Google Gemini API key.\nThis enables grammar correction when you hold \(Config.triggerKey.displayName)+Q while recording.\n\nGet a key at: ai.google.dev"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        // Add text field
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "AIza..."
        
        // Pre-fill with existing key if available
        if let existing = UserDefaults.standard.string(forKey: Config.googleAPIKeyDefaultsKey) {
            input.stringValue = existing
        }
        
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            let key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                GeminiService.configure(apiKey: key)
                geminiMenuItem.title = geminiMenuTitle()
            }
        }
    }
    
    // MARK: - Copy Last Transcription
    
    @objc private func copyLastTranscription() {
        guard let text = stateMachine.lastTranscription else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
