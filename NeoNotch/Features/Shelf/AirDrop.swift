import AppKit

/// Sending through AirDrop, with the system's own device picker.
enum AirDrop {
    static var service: NSSharingService? { NSSharingService(named: .sendViaAirDrop) }

    /// The real AirDrop icon — SF Symbols has no public one.
    static var icon: NSImage? { service?.image }

    /// Opens the AirDrop picker for the items. False when there is nothing
    /// AirDrop can take, or AirDrop is off.
    @discardableResult
    static func send(_ items: [Any]) -> Bool {
        guard !items.isEmpty, let service, service.canPerform(withItems: items) else { return false }
        // The picker is our window; an agent app has to come forward to show it.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items)
        return true
    }
}
