import Foundation
import CoreGraphics

/// A modifier key that can be held to trigger recording.
struct TriggerKey: Equatable {
    let id: String
    let displayName: String
    let keyCode: CGKeyCode
    /// Device-specific NX flag bit (not generic masks like maskControl).
    /// Device bits distinguish left from right, preventing stuck-recording
    /// when both sides of the same modifier family are held simultaneously.
    let deviceFlagMask: UInt64

    static let allOptions: [TriggerKey] = [
        TriggerKey(id: "leftControl",  displayName: "Left Control",  keyCode: 59, deviceFlagMask: 0x00000001),
        TriggerKey(id: "rightControl", displayName: "Right Control", keyCode: 62, deviceFlagMask: 0x00002000),
        TriggerKey(id: "leftOption",   displayName: "Left Option",   keyCode: 58, deviceFlagMask: 0x00000020),
        TriggerKey(id: "rightOption",  displayName: "Right Option",  keyCode: 61, deviceFlagMask: 0x00000040),
        TriggerKey(id: "rightShift",   displayName: "Right Shift",   keyCode: 60, deviceFlagMask: 0x00000004),
        TriggerKey(id: "fn",           displayName: "Fn / Globe",    keyCode: 63, deviceFlagMask: 0x00800000),
    ]

    static let defaultKey = allOptions[0]

    static func from(id: String) -> TriggerKey {
        allOptions.first { $0.id == id } ?? defaultKey
    }
}
