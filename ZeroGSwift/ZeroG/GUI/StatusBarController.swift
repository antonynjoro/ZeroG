import Cocoa
import Combine

// MARK: - Status Bar Controller

/// Manages the macOS status bar (menu bar) icon, dropdown menu, and status text.
final class StatusBarController {
    
    // MARK: Properties
    
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var geminiMenuItem: NSMenuItem!
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
    }
    
    // MARK: - UI Updates
    
    private func updateUI(for state: AppState) {
        guard let button = statusItem.button else { return }
        
        statusMenuItem.title = state.statusText
        
        let symbolName: String
        let tintColor: NSColor
        
        switch state {
        case .loading:
            symbolName = "arrow.down.circle"
            tintColor = .systemOrange
        case .idle:
            symbolName = "mic"
            tintColor = .labelColor
        case .recording:
            symbolName = "mic.fill"
            tintColor = .systemRed
        case .processing:
            symbolName = "waveform.circle"
            tintColor = .labelColor
        case .success:
            symbolName = "checkmark.circle"
            tintColor = .systemGreen
        case .error:
            symbolName = "exclamationmark.triangle"
            tintColor = .systemYellow
        }
        
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ZeroG Status") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configuredImage = image.withSymbolConfiguration(config) ?? image
            
            if tintColor != .labelColor {
                configuredImage.isTemplate = false
                button.contentTintColor = tintColor
            } else {
                configuredImage.isTemplate = true
                button.contentTintColor = nil
            }
            
            button.image = configuredImage
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
        alert.informativeText = "Enter your Google Gemini API key.\nThis enables grammar correction when you hold Control+Q while recording.\n\nGet a key at: ai.google.dev"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        // Add text field
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "AIza..."
        
        // Pre-fill with existing key if available
        if let existing = UserDefaults.standard.string(forKey: "GOOGLE_API_KEY") {
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
}
