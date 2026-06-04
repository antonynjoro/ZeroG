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
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: Dependencies
    
    private let stateMachine: AppStateMachine
    
    // MARK: Initialization
    
    init(stateMachine: AppStateMachine) {
        self.stateMachine = stateMachine
        
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
        
        let symbolName: String
        switch state {
        case .loading:
            symbolName = "arrow.down.circle"
        case .idle:
            symbolName = "mic"
        case .recording:
            symbolName = "mic.fill"
        case .processing:
            symbolName = "waveform.circle"
        case .success:
            symbolName = "checkmark.circle"
        case .error:
            symbolName = "exclamationmark.triangle"
        }
        
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
