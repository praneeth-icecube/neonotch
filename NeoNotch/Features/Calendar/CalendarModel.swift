import AppKit
import EventKit

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let location: String?

    var timeRange: String {
        if isAllDay { return "All day" }
        return "\(Self.time.string(from: start)) – \(Self.time.string(from: end))"
    }

    var isOver: Bool { end < Date() }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

extension CalendarEvent {
    init(_ event: EKEvent) {
        id = event.eventIdentifier ?? event.calendarItemIdentifier
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = title.isEmpty ? "Untitled" : title
        start = event.startDate
        end = event.endDate
        isAllDay = event.isAllDay
        color = event.calendar?.color ?? .systemBlue
        location = event.location
    }
}

/// The Calendar app's events, through EventKit.
///
/// Read-only: NeoNotch shows your schedule and hands off to Calendar for
/// anything else. Needs "Full Access" to events, which macOS asks for once.
final class CalendarModel: ObservableObject {
    enum Access: Equatable { case notDetermined, granted, denied }

    @Published private(set) var access: Access
    /// Start of the day being shown.
    @Published private(set) var selectedDay: Date
    @Published private(set) var events: [CalendarEvent] = []

    private let store = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    /// Set by snapshot seeding, so a reload cannot swap the seed for real data.
    private var isFrozen = false

    init() {
        access = Self.currentAccess()
        selectedDay = Calendar.current.startOfDay(for: Date())

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.reload()
            },
            // Midnight: yesterday's "today" should not linger on screen.
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                self?.select(Date())
            }
        ]
        reload()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Yesterday, today and tomorrow — the strip under the events.
    var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (-1...1).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var isShowingToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    func select(_ day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        if start != selectedDay { selectedDay = start }
        reload()
    }

    func reload() {
        guard !isFrozen else { return }
        let current = Self.currentAccess()
        if access != current { access = current }
        guard access == .granted else {
            if !events.isEmpty { events = [] }
            return
        }
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        let predicate = store.predicateForEvents(withStart: selectedDay, end: end, calendars: nil)
        let fresh = store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map(CalendarEvent.init)
        if fresh != events { events = fresh }
    }

    /// Asks macOS for access, or — if it was refused — opens the settings pane
    /// where it can be given.
    func requestAccess() {
        guard access != .denied else {
            openPrivacySettings()
            return
        }
        store.requestFullAccessToEvents { [weak self] _, error in
            if let error { Trace.log("calendar", "access request failed: \(error.localizedDescription)") }
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Shows the event in Calendar.
    func open(_ event: CalendarEvent) {
        let encoded = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
        if let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        openCalendar()
    }

    func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    #if DEBUG
    func debugSeed(_ seeded: [CalendarEvent]) {
        isFrozen = true
        access = .granted
        events = seeded
    }
    #endif
}
