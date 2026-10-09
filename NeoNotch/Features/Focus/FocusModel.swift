import AppKit
import SwiftUI

/// Pomodoro: focus sessions and breaks, a cycle of sprints, and a daily streak.
///
/// Like the countdown timer it is stored as an end date, never a counter, so
/// it stays exact across sleep and missed ticks. The tick only notices a phase
/// ending and republishes once a second for the closed island's readout.
final class FocusModel: ObservableObject {
    enum Phase: String {
        case focus, shortBreak, longBreak

        var isBreak: Bool { self != .focus }

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
        }

        var symbol: String { isBreak ? "leaf.fill" : "brain.head.profile" }

        /// Blue for focus, green for rest.
        var tint: Color {
            isBreak ? Color(red: 0.2, green: 0.83, blue: 0.6) : Color(red: 0.29, green: 0.64, blue: 1)
        }
    }

    @Published private(set) var phase: Phase = .focus
    /// Which focus session of the cycle this is, 1…`sprints`.
    @Published private(set) var sprint = 1
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    /// Finished focus sessions per day, keyed "yyyy-MM-dd".
    @Published private(set) var history: [String: Int]

    /// A phase ran out: (the one that finished, the one that follows).
    var onPhaseEnd: ((Phase, Phase) -> Void)?

    private let preferences: Preferences
    private var ticker: Timer?
    private var lastPublishedSecond = -1
    private static let historyFile = "focus-history.json"

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        history = Storage.load([String: Int].self, from: Self.historyFile) ?? [:]
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        ticker?.tolerance = 0.05
    }

    deinit {
        ticker?.invalidate()
    }

    var isRunning: Bool { endDate != nil }

    /// Running, or paused partway through a phase.
    var isActive: Bool { isRunning || pausedRemaining != nil }

    var sprints: Int { max(1, preferences.focusSprints) }

    var duration: TimeInterval {
        let minutes: Double = switch phase {
        case .focus: preferences.focusMinutes
        case .shortBreak: preferences.shortBreakMinutes
        case .longBreak: preferences.longBreakMinutes
        }
        return max(60, minutes * 60)
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return duration }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = Date()) -> Double {
        min(max(1 - remaining(at: date) / duration, 0), 1)
    }

    // MARK: Controls

    /// Start, pause or resume.
    func toggle() {
        if let endDate {
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
        } else {
            endDate = Date().addingTimeInterval(pausedRemaining ?? duration)
            pausedRemaining = nil
        }
        lastPublishedSecond = -1
    }

    /// Back to the first focus session, stopped.
    func reset() {
        endDate = nil
        pausedRemaining = nil
        phase = .focus
        sprint = 1
        lastPublishedSecond = -1
    }

    /// Straight on to the next phase. A skipped session does not count
    /// towards the streak.
    func skip() {
        advance(completed: false, keepRunning: isRunning)
    }

    // MARK: Streak

    var completedToday: Int { history[Self.key(for: Date())] ?? 0 }

    /// Days in a row with at least one finished focus session. Today only
    /// counts once it has one, so the streak does not read zero at breakfast.
    var streak: Int { Self.streak(in: history, today: Date()) }

    static func streak(in history: [String: Int], today: Date) -> Int {
        let calendar = Calendar.current
        var day = today
        if (history[key(for: day)] ?? 0) == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var count = 0
        while (history[key(for: day)] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Tick

    private func tick() {
        guard let endDate else { return }
        if endDate.timeIntervalSinceNow <= 0 {
            advance(completed: true, keepRunning: preferences.focusAutoStart)
            return
        }
        let second = Int(remaining().rounded(.up))
        if second != lastPublishedSecond {
            lastPublishedSecond = second
            objectWillChange.send()
        }
    }

    private func advance(completed: Bool, keepRunning: Bool) {
        let finished = phase
        if finished == .focus, completed { recordSession() }

        let next: Phase
        if finished == .focus {
            next = sprint >= sprints ? .longBreak : .shortBreak
        } else {
            next = .focus
            sprint = finished == .longBreak ? 1 : min(sprint + 1, sprints)
        }
        phase = next
        pausedRemaining = nil
        endDate = keepRunning ? Date().addingTimeInterval(duration) : nil
        lastPublishedSecond = -1
        if completed { onPhaseEnd?(finished, next) }
    }

    private func recordSession() {
        history[Self.key(for: Date()), default: 0] += 1
        // A year and a bit is plenty for a streak.
        if history.count > 400 {
            for key in history.keys.sorted().prefix(history.count - 400) { history[key] = nil }
        }
        Storage.save(history, to: Self.historyFile)
    }

    static func key(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    #if DEBUG
    func debugStart(remaining: TimeInterval, phase: Phase = .focus, sprint: Int = 1) {
        self.phase = phase
        self.sprint = sprint
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(remaining)
    }
    #endif
}
