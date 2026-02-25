import Cocoa
import Combine

// MARK: - Status Bar Controller

/// Manages the macOS status bar (menu bar) icon and dropdown menu.
/// Replaces Python's `menu.py` with native AppKit, including proper SF Symbol tinting.
final class StatusBarController {
    
    // MARK: Properties
    
    private var statusItem: NSStatusItem!
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
        
        let quitItem = NSMenuItem(
            title: "Quit ZeroG",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        
        // Set initial icon
        updateIcon(for: .idle)
    }
    
    // MARK: - State Observation
    
    private func observeState() {
        stateMachine.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Icon Updates
    
    private func updateIcon(for state: AppState) {
        guard let button = statusItem.button else { return }
        
        let symbolName: String
        let tintColor: NSColor
        
        switch state {
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
            // Create a tinted version of the SF Symbol
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configuredImage = image.withSymbolConfiguration(config) ?? image
            
            if tintColor != .labelColor {
                // Apply tint color — use non-template mode for colored icons
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
