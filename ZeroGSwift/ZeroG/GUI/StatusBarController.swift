import Cocoa
import Combine

// MARK: - Status Bar Controller

/// Manages the macOS status bar (menu bar) icon, dropdown menu, and status text.
final class StatusBarController {
    
    // MARK: Properties
    
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    /// Shown only while the key tap is dead (Accessibility missing, so the
    /// hotkey can't fire). Hidden once the tap is live.
    private var hotkeyDisabledMenuItem: NSMenuItem!
    private var copyTranscriptionMenuItem: NSMenuItem!
    private var triggerKeySubmenu: NSMenu!
    private var cancellables = Set<AnyCancellable>()

    // MARK: Dependencies

    private let stateMachine: AppStateMachine

    /// Opens the permissions / setup wizard.
    private let onShowPermissions: () -> Void

    // MARK: Initialization

    init(stateMachine: AppStateMachine,
         onShowPermissions: @escaping () -> Void = {}) {
        self.stateMachine = stateMachine
        self.onShowPermissions = onShowPermissions

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

        // Hotkey-disabled warning (hidden unless the key tap is dead — Accessibility missing)
        hotkeyDisabledMenuItem = NSMenuItem(title: "Hotkey disabled — open Setup", action: nil, keyEquivalent: "")
        hotkeyDisabledMenuItem.isEnabled = false
        hotkeyDisabledMenuItem.isHidden = true
        menu.addItem(hotkeyDisabledMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Setup / Permissions wizard
        let setupItem = NSMenuItem(
            title: "Setup / Permissions…",
            action: #selector(showPermissions),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

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

        // Menu symbol comes from the single state-presentation source of truth.
        let symbolName = state.presentation.menuSymbol

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

    // MARK: - Permissions / Setup

    @objc private func showPermissions() {
        onShowPermissions()
    }

    /// Reflect whether the hotkey tap is live. Shows the "Hotkey disabled" line
    /// in the menu when the key tap isn't running (Accessibility missing).
    func updateHotkeyStatus(hotkeyLive: Bool) {
        hotkeyDisabledMenuItem.isHidden = hotkeyLive
    }

    // MARK: - Copy Last Transcription
    
    @objc private func copyLastTranscription() {
        guard let text = stateMachine.lastTranscription else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
