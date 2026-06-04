import Foundation
import Cocoa
import CoreGraphics

// MARK: - Text Injector

/// Injects transcribed text into the currently focused application using the clipboard.
/// Replaces Python's `typer.py` + `clipboard.py` with native AppKit / CoreGraphics.
///
/// ## Strategy
/// 1. Snapshot the current clipboard (all pasteboard items + types)
/// 2. Write the transcribed text to the clipboard
/// 3. Simulate Cmd+V to paste
/// 4. Restore the original clipboard after a short delay
///
/// This ensures the user's clipboard isn't destroyed by the injection.
enum TextInjector {
    
    /// Inject text into the focused application by pasting from clipboard.
    ///
    /// - Parameter text: The text to inject.
    static func injectText(_ text: String) {
        guard !text.isEmpty else { return }
        
        let pasteboard = NSPasteboard.general
        
        // 1. Snapshot current clipboard
        let snapshot = snapshotClipboard(pasteboard)
        
        // 2. Write our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Simulate Cmd+V
        simulatePaste()
        
        // 4. Restore clipboard after a delay
        if let snapshot = snapshot, !snapshot.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.Timing.clipboardRestore) {
                restoreClipboard(snapshot, to: pasteboard)
            }
        }
        
        #if DEBUG
        let preview = text.count > 40 ? String(text.prefix(40)) + "..." : text
        print("[TextInjector] Injected: '\(preview)' (\(text.count) chars)")
        #endif
    }
    
    // MARK: - Clipboard Snapshot / Restore
    
    /// Capture the full state of the pasteboard (all items and their type-specific data).
    private static func snapshotClipboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]]? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        
        var snapshot: [[(NSPasteboard.PasteboardType, Data)]] = []
        
        for item in items {
            var itemData: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData.append((type, data))
                }
            }
            if !itemData.isEmpty {
                snapshot.append(itemData)
            }
        }
        
        return snapshot
    }
    
    /// Restore the pasteboard to a previously captured snapshot.
    private static func restoreClipboard(_ snapshot: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        
        for itemData in snapshot {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
        
        #if DEBUG
        print("[TextInjector] Clipboard restored (\(snapshot.count) items).")
        #endif
    }
    
    // MARK: - Keyboard Simulation
    
    /// Simulate pressing Cmd+V to paste from clipboard.
    private static func simulatePaste() {
        let vKeyCode: CGKeyCode = 0x09 // 'V' key
        let cmdKeyCode: CGKeyCode = 0x37 // Left Command key
        
        // Create events with an explicit HID event source for isolation
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Cmd Down
        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.post(tap: .cgSessionEventTap)
        }
        
        // V Down (with Cmd held)
        if let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.post(tap: .cgSessionEventTap)
        }
        
        // V Up
        if let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.post(tap: .cgSessionEventTap)
        }
        
        // Cmd Up
        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) {
            cmdUp.post(tap: .cgSessionEventTap)
        }
    }
}
