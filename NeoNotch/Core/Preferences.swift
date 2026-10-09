import SwiftUI

/// User-tunable settings, persisted in `UserDefaults`.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: Appearance

    /// Width of the synthesised notch on displays without a camera housing.
    @Published var virtualNotchWidth: CGFloat { didSet { store(virtualNotchWidth, .virtualNotchWidth) } }
    /// Height of the synthesised notch. Clamped to the menu bar height at use time.
    @Published var virtualNotchHeight: CGFloat { didSet { store(virtualNotchHeight, .virtualNotchHeight) } }
    /// Draw a virtual notch even on a Mac that has a real one. Handy for testing.
    @Published var forceVirtualNotch: Bool { didSet { store(forceVirtualNotch, .forceVirtualNotch) } }
    /// Manual left/right calibration in points, applied on top of exact centring.
    ///
    /// The island is centred on the display's logical frame, which is correct to
    /// the pixel. A laptop's active panel is not always centred within its lid
    /// though, so screen-centred can still read as off-centre against the case.
    /// Negative nudges left, positive nudges right.
    @Published var horizontalOffset: CGFloat { didSet { store(horizontalOffset, .horizontalOffset) } }
    /// Width of the island while a task is running.
    ///
    /// The closed island only ever grows sideways — it stays exactly menu bar
    /// height so it never reaches down into the workspace. The cost is that
    /// macOS lays the menu bar out with no idea the island exists, so every
    /// extra 2 pt of width covers 1 pt of the frontmost app's menus on each
    /// side. That is a deliberate trade: staying out of the working area
    /// matters more than the tail of a menu.
    @Published var busyWidth: CGFloat { didSet { store(busyWidth, .busyWidth) } }

    // MARK: Behaviour

    /// Open the panel when the pointer rests on the notch.
    @Published var openOnHover: Bool { didSet { store(openOnHover, .openOnHover) } }
    /// Seconds the pointer must linger before the panel opens.
    @Published var hoverOpenDelay: Double { didSet { store(hoverOpenDelay, .hoverOpenDelay) } }
    /// Global keyboard shortcut that opens and closes the notch.
    @Published var toggleShortcut: NotchShortcut { didSet { store(toggleShortcut.rawValue, .toggleShortcut) } }

    // MARK: Home

    /// Widgets on the Home tab, in order. A widget that is not listed is off.
    @Published var homeModules: [HomeModule] { didSet { store(homeModules.map(\.rawValue), .homeModules) } }

    // MARK: Features

    @Published var clipboardHistoryLimit: Int { didSet { store(clipboardHistoryLimit, .clipboardHistoryLimit) } }
    @Published var clipboardEnabled: Bool { didSet { store(clipboardEnabled, .clipboardEnabled) } }
    @Published var ignoreConcealedClipboardItems: Bool { didSet { store(ignoreConcealedClipboardItems, .ignoreConcealedClipboardItems) } }
    /// Keep text and file history across restarts. Images stay in memory only.
    @Published var keepClipboardHistory: Bool { didSet { store(keepClipboardHistory, .keepClipboardHistory) } }

    // MARK: Focus

    @Published var focusMinutes: Double { didSet { store(focusMinutes, .focusMinutes) } }
    @Published var shortBreakMinutes: Double { didSet { store(shortBreakMinutes, .shortBreakMinutes) } }
    @Published var longBreakMinutes: Double { didSet { store(longBreakMinutes, .longBreakMinutes) } }
    /// Focus sessions per cycle; the break after the last one is the long one.
    @Published var focusSprints: Int { didSet { store(focusSprints, .focusSprints) } }
    /// Roll straight into the next phase instead of waiting for a press.
    @Published var focusAutoStart: Bool { didSet { store(focusAutoStart, .focusAutoStart) } }
    @Published var focusSound: Bool { didSet { store(focusSound, .focusSound) } }

    // MARK: Battery and camera

    /// The charge capsule in the panel header.
    @Published var showBattery: Bool { didSet { store(showBattery, .showBattery) } }
    /// Show the closed notch briefly when you plug in, and warn at 20% and 10%.
    @Published var batteryAlerts: Bool { didSet { store(batteryAlerts, .batteryAlerts) } }
    /// Flip the camera preview so it behaves like a mirror.
    @Published var mirrorFlip: Bool { didSet { store(mirrorFlip, .mirrorFlip) } }

    /// Shipping values, in one place so "Reset to defaults" and a first launch
    /// cannot drift apart.
    enum Default {
        static let virtualNotchWidth: CGFloat = 210
        static let virtualNotchHeight: CGFloat = 32
        static let forceVirtualNotch = false
        static let horizontalOffset: CGFloat = 0
        static let busyWidth: CGFloat = 320
        static let openOnHover = true
        /// Zero: the notch should be open by the time you notice you moved
        /// there. The setting stays for anyone who wants a dwell delay.
        static let hoverOpenDelay: Double = 0
        static let toggleShortcut: NotchShortcut = .controlOptionN
        static let homeModules: [HomeModule] = HomeModule.standard
        static let clipboardHistoryLimit = 50
        static let clipboardEnabled = true
        static let ignoreConcealedClipboardItems = true
        static let keepClipboardHistory = true
        static let focusMinutes: Double = 25
        static let shortBreakMinutes: Double = 5
        static let longBreakMinutes: Double = 15
        static let focusSprints = 4
        static let focusAutoStart = true
        static let focusSound = true
        static let showBattery = true
        static let batteryAlerts = true
        static let mirrorFlip = true
    }

    private init() {
        virtualNotchWidth = defaults.value(for: .virtualNotchWidth) ?? Default.virtualNotchWidth
        virtualNotchHeight = defaults.value(for: .virtualNotchHeight) ?? Default.virtualNotchHeight
        forceVirtualNotch = defaults.value(for: .forceVirtualNotch) ?? Default.forceVirtualNotch
        horizontalOffset = defaults.value(for: .horizontalOffset) ?? Default.horizontalOffset
        busyWidth = defaults.value(for: .busyWidth) ?? Default.busyWidth
        openOnHover = defaults.value(for: .openOnHover) ?? Default.openOnHover
        hoverOpenDelay = defaults.value(for: .hoverOpenDelay) ?? Default.hoverOpenDelay
        toggleShortcut = (defaults.value(for: .toggleShortcut) as String?)
            .flatMap(NotchShortcut.init(rawValue:)) ?? Default.toggleShortcut
        homeModules = (defaults.value(for: .homeModules) as [String]?)
            .map { $0.compactMap(HomeModule.init(rawValue:)) } ?? Default.homeModules
        clipboardHistoryLimit = defaults.value(for: .clipboardHistoryLimit) ?? Default.clipboardHistoryLimit
        clipboardEnabled = defaults.value(for: .clipboardEnabled) ?? Default.clipboardEnabled
        ignoreConcealedClipboardItems = defaults.value(for: .ignoreConcealedClipboardItems)
            ?? Default.ignoreConcealedClipboardItems
        keepClipboardHistory = defaults.value(for: .keepClipboardHistory) ?? Default.keepClipboardHistory
        focusMinutes = defaults.value(for: .focusMinutes) ?? Default.focusMinutes
        shortBreakMinutes = defaults.value(for: .shortBreakMinutes) ?? Default.shortBreakMinutes
        longBreakMinutes = defaults.value(for: .longBreakMinutes) ?? Default.longBreakMinutes
        focusSprints = defaults.value(for: .focusSprints) ?? Default.focusSprints
        focusAutoStart = defaults.value(for: .focusAutoStart) ?? Default.focusAutoStart
        focusSound = defaults.value(for: .focusSound) ?? Default.focusSound
        showBattery = defaults.value(for: .showBattery) ?? Default.showBattery
        batteryAlerts = defaults.value(for: .batteryAlerts) ?? Default.batteryAlerts
        mirrorFlip = defaults.value(for: .mirrorFlip) ?? Default.mirrorFlip

        // Once: Timer took Calendar's place on Home, and Notes arrived next
        // to Reminders. Calendar stays one click away in Settings.
        if (defaults.value(for: .homeLayoutVersion) ?? 1) < 2 {
            var modules = homeModules
            if let calendar = modules.firstIndex(of: .calendar) {
                modules[calendar] = .timer
            } else if !modules.contains(.timer) {
                modules.insert(.timer, at: min(1, modules.count))
            }
            if !modules.contains(.notes) {
                let after = modules.firstIndex(of: .reminders).map { $0 + 1 } ?? modules.endIndex
                modules.insert(.notes, at: after)
            }
            homeModules = modules
            store(modules.map(\.rawValue), .homeModules)
            store(2, .homeLayoutVersion)
        }
    }

    /// Puts every setting back to its shipping value.
    func resetToDefaults() {
        virtualNotchWidth = Default.virtualNotchWidth
        virtualNotchHeight = Default.virtualNotchHeight
        forceVirtualNotch = Default.forceVirtualNotch
        horizontalOffset = Default.horizontalOffset
        busyWidth = Default.busyWidth
        openOnHover = Default.openOnHover
        hoverOpenDelay = Default.hoverOpenDelay
        toggleShortcut = Default.toggleShortcut
        homeModules = Default.homeModules
        clipboardHistoryLimit = Default.clipboardHistoryLimit
        clipboardEnabled = Default.clipboardEnabled
        ignoreConcealedClipboardItems = Default.ignoreConcealedClipboardItems
        keepClipboardHistory = Default.keepClipboardHistory
        focusMinutes = Default.focusMinutes
        shortBreakMinutes = Default.shortBreakMinutes
        longBreakMinutes = Default.longBreakMinutes
        focusSprints = Default.focusSprints
        focusAutoStart = Default.focusAutoStart
        focusSound = Default.focusSound
        showBattery = Default.showBattery
        batteryAlerts = Default.batteryAlerts
        mirrorFlip = Default.mirrorFlip
    }

    /// True when nothing has been changed from the shipping values, so the
    /// reset control can tell you there is nothing to undo.
    var isAtDefaults: Bool {
        virtualNotchWidth == Default.virtualNotchWidth
            && virtualNotchHeight == Default.virtualNotchHeight
            && forceVirtualNotch == Default.forceVirtualNotch
            && horizontalOffset == Default.horizontalOffset
            && busyWidth == Default.busyWidth
            && openOnHover == Default.openOnHover
            && hoverOpenDelay == Default.hoverOpenDelay
            && toggleShortcut == Default.toggleShortcut
            && homeModules == Default.homeModules
            && clipboardHistoryLimit == Default.clipboardHistoryLimit
            && clipboardEnabled == Default.clipboardEnabled
            && ignoreConcealedClipboardItems == Default.ignoreConcealedClipboardItems
            && keepClipboardHistory == Default.keepClipboardHistory
            && focusMinutes == Default.focusMinutes
            && shortBreakMinutes == Default.shortBreakMinutes
            && longBreakMinutes == Default.longBreakMinutes
            && focusSprints == Default.focusSprints
            && focusAutoStart == Default.focusAutoStart
            && focusSound == Default.focusSound
            && showBattery == Default.showBattery
            && batteryAlerts == Default.batteryAlerts
            && mirrorFlip == Default.mirrorFlip
    }

    // MARK: Home editing

    func setModule(_ module: HomeModule, enabled: Bool) {
        if enabled {
            guard !homeModules.contains(module) else { return }
            // Back in its shipping position relative to the others.
            let order = HomeModule.allCases
            let index = homeModules.firstIndex { order.firstIndex(of: $0)! > order.firstIndex(of: module)! }
            homeModules.insert(module, at: index ?? homeModules.endIndex)
        } else {
            homeModules.removeAll { $0 == module }
        }
    }

    /// Moves a widget one place left (-1) or right (+1).
    func moveModule(_ module: HomeModule, by step: Int) {
        guard let index = homeModules.firstIndex(of: module) else { return }
        let target = index + step
        guard homeModules.indices.contains(target) else { return }
        homeModules.swapAt(index, target)
    }

    private func store<T>(_ value: T, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    enum Key: String {
        case virtualNotchWidth, virtualNotchHeight, forceVirtualNotch, horizontalOffset
        case busyWidth
        case openOnHover, hoverOpenDelay, toggleShortcut
        case homeModules, homeLayoutVersion
        case clipboardHistoryLimit, clipboardEnabled, ignoreConcealedClipboardItems, keepClipboardHistory
        case focusMinutes, shortBreakMinutes, longBreakMinutes, focusSprints, focusAutoStart, focusSound
        case showBattery, batteryAlerts, mirrorFlip
    }
}

private extension UserDefaults {
    func value<T>(for key: Preferences.Key) -> T? {
        object(forKey: key.rawValue) as? T
    }
}
