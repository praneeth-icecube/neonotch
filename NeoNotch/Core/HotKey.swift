import AppKit
import Carbon.HIToolbox

/// Shortcuts offered for opening the notch from the keyboard.
///
/// A short fixed list rather than a recorder: each of these is free on a stock
/// Mac. The obvious candidates are taken — ⌃Space and ⌃⌥Space switch input
/// sources, ⌘Space and ⌥⌘Space belong to Spotlight.
enum NotchShortcut: String, CaseIterable, Identifiable {
    case off
    case controlOptionN
    case controlOptionCommandN
    case optionCommandBackslash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .controlOptionN: "⌃⌥N"
        case .controlOptionCommandN: "⌃⌥⌘N"
        case .optionCommandBackslash: "⌥⌘\\"
        }
    }

    fileprivate var carbon: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionN: (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey))
        case .controlOptionCommandN: (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey))
        case .optionCommandBackslash: (UInt32(kVK_ANSI_Backslash), UInt32(optionKey | cmdKey))
        }
    }
}

/// One system-wide hot key, through Carbon's `RegisterEventHotKey`.
///
/// That API needs no Accessibility permission — unlike an `NSEvent` global
/// monitor for key-downs — which is why it is still the right tool for an
/// agent app. The press arrives on the main thread.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    /// Replaces whatever was registered before. Returns false when macOS
    /// refused the combination (another app already owns it).
    @discardableResult
    func register(_ shortcut: NotchShortcut) -> Bool {
        unregister()
        guard let combination = shortcut.carbon else { return true }
        installHandlerIfNeeded()

        let identifier = EventHotKeyID(signature: OSType(0x4E4E_4F54), id: 1) // 'NNOT'
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        Trace.log("hotkey", "register \(shortcut.title): \(status)")
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { center.onPress?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
