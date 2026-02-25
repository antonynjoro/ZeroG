import Cocoa
import Combine

// MARK: - Status Bar Controller

/// Manages the macOS status bar (menu bar) icon, dropdown menu, and status text.
final class StatusBarController {
    
    // MARK: Properties
    
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
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
        
        // Build the dropdown menu
        let menu = NSMenu()
        
        // Status text (non-clickable, shows current state)
        statusMenuItem = NSMenuItem(title: "Starting up...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit ZeroG",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        
        // Set initial icon
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
        
        // Update status text in the menu
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
}
