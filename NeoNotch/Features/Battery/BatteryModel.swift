import AppKit
import IOKit.ps

/// Charge level and power state of the internal battery.
///
/// Updated by IOKit's power-source notification rather than polled, so it
/// costs nothing between changes. On a Mac without a battery `level` is nil
/// and everything that shows it stays hidden.
final class BatteryModel: ObservableObject {
    enum Event {
        /// The charger went in; the closed notch shows it for a moment.
        case pluggedIn(level: Int)
        /// Crossed 20% or 10% while running on battery.
        case low(level: Int)
    }

    @Published private(set) var level: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false

    var onEvent: ((Event) -> Void)?

    private var source: CFRunLoopSource?
    private var hasReading = false
    private static let warningLevels = [20, 10]

    init() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<BatteryModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { model.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for entry in list {
            guard let description = IOPSGetPowerSourceDescription(info, entry)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(1, description[kIOPSMaxCapacityKey] as? Int ?? 100)
            let newLevel = Int((Double(current) / Double(maximum) * 100).rounded())
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            apply(level: min(max(newLevel, 0), 100), charging: charging, pluggedIn: pluggedIn)
            return
        }
    }

    private func apply(level newLevel: Int, charging: Bool, pluggedIn: Bool) {
        let previousLevel = level
        let wasPluggedIn = isPluggedIn

        if level != newLevel { level = newLevel }
        if isCharging != charging { isCharging = charging }
        if isPluggedIn != pluggedIn { isPluggedIn = pluggedIn }

        // The very first reading is a state, not an event.
        guard hasReading else {
            hasReading = true
            return
        }
        if pluggedIn, !wasPluggedIn {
            onEvent?(.pluggedIn(level: newLevel))
        } else if !pluggedIn, let previousLevel,
                  Self.warningLevels.contains(where: { previousLevel > $0 && newLevel <= $0 }) {
            onEvent?(.low(level: newLevel))
        }
    }

    #if DEBUG
    func debugSet(level: Int, charging: Bool) {
        self.level = level
        isCharging = charging
        isPluggedIn = charging
    }
    #endif
}
