import AppKit
import Combine

/// A single countdown. Stored as an end date so it stays accurate across sleep
/// and across ticks we happen to miss.
struct NotchCountdown: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var duration: TimeInterval
    var endDate: Date?
    /// Time left when paused; nil while running.
    var pausedRemaining: TimeInterval?
    /// Set while this is a timer in Apple's Clock app rather than NeoNotch's own.
    var clockID: String?

    var isRunning: Bool { endDate != nil }
    var isClock: Bool { clockID != nil }

    /// A title given in Clock, if any.
    var customTitle: String? { label == Self.format(duration) ? nil : label }
    /// What Clock calls it: its title, or its length — "1 hr", "5 min".
    var name: String { customTitle ?? Self.words(for: duration) }

    /// "1 hr", "5 min", "1 hr 30 min", "45 sec" — how Clock names a timer.
    static func words(for interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let parts = [(total / 3600, "hr"), ((total % 3600) / 60, "min"), (total % 60, "sec")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "0 sec" : parts.joined(separator: " ")
    }

    /// Sampled at an arbitrary instant so a view can read it once per frame
    /// rather than waiting to be told it changed.
    func remaining(at date: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return duration }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - min(max(remaining(at: date) / duration, 0), 1)
    }

    var remainingLabel: String { NotchCountdown.format(remaining()) }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Stopwatch style, with hundredths.
    static func formatPrecise(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let total = Int(clamped)
        let hundredths = Int((clamped - Double(total)) * 100)
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d.%02d", minutes / 60, minutes % 60, seconds, hundredths)
        }
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
    }
}

/// A length used recently — the Recents list down the side of the Timer tab,
/// kept the way Apple's Clock keeps its own.
struct TimerRecent: Identifiable, Equatable {
    let duration: TimeInterval
    var id: TimeInterval { duration }
}

/// Countdown timers plus a stopwatch — NeoNotch's own, or Apple Clock's.
///
/// Both are stored as dates, never as accumulating counters, and views sample
/// them per frame through `TimelineView`. The model's own tick exists only to
/// notice a timer finishing and to refresh the once-a-second label in the closed
/// island — it is not what drives the display. Publishing at tick rate is what
/// made the stopwatch step in quarter-seconds while showing hundredths.
///
/// A timer or stopwatch running in Clock shows here as if it were NeoNotch's,
/// and with the shortcuts `ClockBridge` looks for, starting one here starts it
/// in Clock instead. NeoNotch's own keep the notch while they run.
final class TimerModel: ObservableObject {
    @Published var active: NotchCountdown?
    /// NeoNotch's own stopwatch; `isStopwatchRunning` also counts Clock's.
    @Published private(set) var isOwnStopwatchRunning = false
    /// A timer just ran out. The closed notch rings for `alertDuration`, then
    /// this clears itself — it never holds the panel open.
    @Published private(set) var didFire = false
    /// Custom duration the user is dialing in, in seconds.
    @Published var draftDuration: TimeInterval = 5 * 60
    /// Lengths started lately, newest first.
    @Published private(set) var recents: [TimerRecent]
    /// Splits of NeoNotch's own stopwatch, oldest first.
    @Published private(set) var laps: [TimeInterval] = []

    /// Off for snapshots, which start timers that are not yours to remember.
    static var remembersRecents = true
    private static let recentsKey = "timerRecents"
    /// What Recents shows before anything has been started.
    private static let starterRecents: [TimeInterval] = [60, 180, 300, 600, 900, 1500, 3600]

    /// Called when one of NeoNotch's own timers finishes, for the system
    /// notification. Clock rings its own.
    var onFire: (() -> Void)?

    /// Apple Clock: seen always, driven through your shortcuts.
    let clock: ClockBridge

    /// How long "Time's up" stays in the closed notch.
    static let alertDuration: TimeInterval = 6
    /// Stands in for a timer sent to Clock until Clock reports it back.
    static let pendingClockID = "pending"

    private var ticker: Timer?
    private var alertExpiry: DispatchWorkItem?
    private var stopwatchStart: Date?
    private var stopwatchAccumulated: TimeInterval = 0
    /// Whole second last published, so we redraw the island once a second
    /// instead of on every tick.
    private var lastPublishedSecond = -1
    private var clockChanges: AnyCancellable?

    init(clock: ClockBridge = ClockBridge()) {
        self.clock = clock
        let saved = Self.remembersRecents
            ? UserDefaults.standard.array(forKey: Self.recentsKey) as? [Double]
            : nil
        recents = (saved ?? Self.starterRecents).map(TimerRecent.init)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        ticker?.tolerance = 0.05
        clockChanges = clock.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.followClock()
                self?.objectWillChange.send()
            }
        // The bridge has already read Clock by now; a change is not the only
        // way to learn of a timer — one running at launch never changes.
        followClock()
    }

    deinit {
        ticker?.invalidate()
    }

    var hasRunningTimer: Bool { active?.isRunning == true }

    // MARK: Countdown

    /// Starts a countdown — in Clock when the Start Timer shortcut exists,
    /// otherwise here.
    func start(seconds: TimeInterval, label: String? = nil) {
        guard seconds > 0 else { return }
        cancelAlertExpiry()
        didFire = false
        lastPublishedSecond = -1
        remember(seconds)

        // The shortcut takes whole minutes; anything finer stays here.
        let isWholeMinutes = seconds.truncatingRemainder(dividingBy: 60) == 0
        let sentToClock = isWholeMinutes && clock.perform(.startTimer, input: "\(Int(seconds / 60))")
        // Shown at once either way. Clock's own replaces it as soon as Clock
        // reports it — matched by when it ends.
        active = NotchCountdown(
            label: label ?? NotchCountdown.format(seconds),
            duration: seconds,
            endDate: Date().addingTimeInterval(seconds),
            pausedRemaining: nil,
            clockID: sentToClock ? Self.pendingClockID : nil
        )
        if sentToClock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.giveUpOnClockStart()
            }
        }
    }

    /// Puts a length at the top of Recents, once.
    private func remember(_ seconds: TimeInterval) {
        var durations = recents.map(\.duration).filter { $0 != seconds }
        durations.insert(seconds, at: 0)
        durations = Array(durations.prefix(12))
        recents = durations.map(TimerRecent.init)
        if Self.remembersRecents {
            UserDefaults.standard.set(durations, forKey: Self.recentsKey)
        }
    }

    enum DraftComponent { case hours, minutes, seconds }

    /// Steps one column of the duration picker, wrapping round like Clock's
    /// wheels do.
    func stepDraft(_ component: DraftComponent, by delta: Int) {
        let total = Int(draftDuration)
        var hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        switch component {
        case .hours: hours = (hours + delta + 24) % 24
        case .minutes: minutes = (minutes + delta + 60) % 60
        case .seconds: seconds = (seconds + delta + 60) % 60
        }
        draftDuration = TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    /// Clock never reported the timer — the shortcut failed or is not what
    /// NeoNotch expects. Keep it here instead, so it still rings.
    private func giveUpOnClockStart() {
        guard active?.clockID == Self.pendingClockID else { return }
        active?.clockID = nil
        Trace.log("clock", "Clock never reported the timer; kept it in NeoNotch")
        clock.reportFailure(.startTimer)
    }

    /// Whether a control works on the countdown showing: always for
    /// NeoNotch's own, and for Clock's only through its shortcut.
    func canControl(_ command: ClockBridge.Command) -> Bool {
        guard let active, active.isClock else { return true }
        return active.clockID != Self.pendingClockID && clock.has(command)
    }

    func pause() {
        guard var timer = active, timer.isRunning else { return }
        if timer.isClock, !(canControl(.pauseTimer) && clock.perform(.pauseTimer)) { return }
        timer.pausedRemaining = timer.remaining()
        timer.endDate = nil
        active = timer
    }

    func resume() {
        guard var timer = active, let remaining = timer.pausedRemaining else { return }
        if timer.isClock, !(canControl(.resumeTimer) && clock.perform(.resumeTimer)) { return }
        timer.endDate = Date().addingTimeInterval(remaining)
        timer.pausedRemaining = nil
        active = timer
    }

    func cancel() {
        if let active, active.isClock {
            guard canControl(.cancelTimer), clock.perform(.cancelTimer) else { return }
        }
        cancelAlertExpiry()
        active = nil
        didFire = false
    }

    /// NeoNotch's own timers only: Clock has no action to add time.
    func addTime(_ seconds: TimeInterval) {
        guard var timer = active else {
            draftDuration = max(0, draftDuration + seconds)
            return
        }
        guard !timer.isClock else { return }
        let wasNamedByLength = timer.customTitle == nil
        if let endDate = timer.endDate {
            timer.endDate = endDate.addingTimeInterval(seconds)
        } else if let paused = timer.pausedRemaining {
            timer.pausedRemaining = max(0, paused + seconds)
        }
        timer.duration = max(timer.duration + seconds, 1)
        if wasNamedByLength { timer.label = NotchCountdown.format(timer.duration) }
        active = timer
    }

    /// Puts Clock's timer on the notch, and keeps it in step: paused, resumed
    /// or stopped in Clock, it follows here within a second.
    private func followClock() {
        // A finished timer is still ringing; NeoNotch's own timer keeps the notch.
        guard !didFire else { return }
        if let active, !active.isClock { return }

        let timers = clock.timers
        let chosen: ClockTimer?
        if let active, active.clockID == Self.pendingClockID, let end = active.endDate {
            // Waiting for the one just sent: the Clock timer ending then.
            chosen = timers.first { abs(($0.endDate ?? .distantFuture).timeIntervalSince(end)) < 10 }
            guard chosen != nil else { return }
        } else if let id = active?.clockID, let same = timers.first(where: { $0.id == id }) {
            chosen = same
        } else {
            chosen = timers.first
        }

        guard let chosen else {
            // Gone from Clock. If its time was up, `tick` rings it here;
            // otherwise it was stopped there.
            if let active, let end = active.endDate, end <= Date().addingTimeInterval(1) { return }
            if active != nil { active = nil }
            return
        }

        let label = chosen.title.isEmpty ? NotchCountdown.format(chosen.duration) : chosen.title
        if var current = active, current.clockID == chosen.id {
            // The same timer: touch only what changed, so nothing redraws for nothing.
            guard current.endDate != chosen.endDate
                || current.pausedRemaining != chosen.pausedRemaining
                || current.duration != chosen.duration
                || current.label != label
            else { return }
            current.endDate = chosen.endDate
            current.pausedRemaining = chosen.pausedRemaining
            current.duration = chosen.duration
            current.label = label
            active = current
        } else {
            lastPublishedSecond = -1
            active = NotchCountdown(
                label: label,
                duration: chosen.duration,
                endDate: chosen.endDate,
                pausedRemaining: chosen.pausedRemaining,
                clockID: chosen.id
            )
        }
    }

    // MARK: Stopwatch

    /// Clock's stopwatch, while it has time on it and NeoNotch's own has none.
    var clockStopwatch: ClockStopwatch? {
        guard !isOwnStopwatchRunning, stopwatchAccumulated < 0.001 else { return nil }
        return clock.stopwatch
    }

    var isStopwatchRunning: Bool {
        isOwnStopwatchRunning || clockStopwatch?.isRunning == true
    }

    /// Elapsed time at an arbitrary instant. Derived from the start date, so it
    /// is exact no matter how often anyone asks.
    func stopwatchElapsed(at date: Date = Date()) -> TimeInterval {
        if let clockStopwatch { return clockStopwatch.elapsed(at: date) }
        guard let stopwatchStart else { return stopwatchAccumulated }
        return stopwatchAccumulated + date.timeIntervalSince(stopwatchStart)
    }

    var hasStopwatchTime: Bool { stopwatchElapsed() > 0.001 }

    /// Whether Start/Stop can do anything: always for NeoNotch's own, and for
    /// Clock's only through its shortcut.
    var canToggleStopwatch: Bool {
        guard let clockStopwatch else { return true }
        return clock.has(clockStopwatch.isRunning ? .stopStopwatch : .startStopwatch)
    }

    var canResetStopwatch: Bool {
        guard clockStopwatch != nil else { return hasStopwatchTime }
        return clock.has(.resetStopwatch)
    }

    /// Laps are NeoNotch's own; Clock's stopwatch keeps its laps in Clock.
    var canLap: Bool { clockStopwatch == nil && isOwnStopwatchRunning }

    func lapStopwatch() {
        guard canLap else { return }
        laps.append(stopwatchElapsed() - laps.reduce(0, +))
    }

    func toggleStopwatch() {
        if let clockStopwatch {
            clock.perform(clockStopwatch.isRunning ? .stopStopwatch : .startStopwatch)
            return
        }
        // A fresh start goes to Clock when the shortcut exists; it shows here
        // as soon as Clock reports it.
        if !isOwnStopwatchRunning, stopwatchAccumulated < 0.001, clock.perform(.startStopwatch) {
            return
        }
        if isOwnStopwatchRunning {
            stopwatchAccumulated = stopwatchElapsed()
            stopwatchStart = nil
            isOwnStopwatchRunning = false
        } else {
            stopwatchStart = Date()
            isOwnStopwatchRunning = true
        }
        lastPublishedSecond = -1
    }

    func resetStopwatch() {
        if clockStopwatch != nil {
            clock.perform(.resetStopwatch)
            return
        }
        stopwatchStart = nil
        stopwatchAccumulated = 0
        isOwnStopwatchRunning = false
        laps = []
        objectWillChange.send()
    }

    // MARK: Tick

    private func tick() {
        if let timer = active, timer.isRunning, timer.remaining() <= 0 {
            fire()
            return
        }

        // Every tick, not only when Clock changes: a Clock timer that started
        // while NeoNotch's own was running must take the notch the moment
        // that one ends, and nothing about Clock changes then.
        followClock()

        // Redraw the closed island only when its once-a-second label changes.
        guard hasRunningTimer || isStopwatchRunning else { return }
        let second = hasRunningTimer
            ? Int((active?.remaining() ?? 0).rounded(.up))
            : Int(stopwatchElapsed())
        if second != lastPublishedSecond {
            lastPublishedSecond = second
            objectWillChange.send()
        }
    }

    /// A small ring, not an alarm: a chime, "Time's up" in the closed notch for
    /// a few seconds, and then it clears itself. Clock's timers get the ring
    /// but not the chime — Clock sounds its own alert.
    ///
    /// It used to pop the panel open and hold it there until you pressed
    /// Dismiss — nothing else, not clicking away or moving the pointer off it,
    /// would close it.
    private func fire() {
        let isClock = active?.isClock == true
        active?.endDate = nil
        active?.pausedRemaining = 0
        didFire = true
        if !isClock {
            NSSound(named: "Glass")?.play()
            onFire?()
        }

        cancelAlertExpiry()
        let expiry = DispatchWorkItem { [weak self] in self?.acknowledgeFire() }
        alertExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.alertDuration, execute: expiry)
    }

    func acknowledgeFire() {
        cancelAlertExpiry()
        didFire = false
        active = nil
    }

    /// A timer started while the last one is still ringing must not be
    /// cleared by that one's expiry.
    private func cancelAlertExpiry() {
        alertExpiry?.cancel()
        alertExpiry = nil
    }

    #if DEBUG
    /// Rings as if a timer had just run out.
    func debugFire() {
        if active == nil {
            active = NotchCountdown(label: "5:00", duration: 300, endDate: Date(), pausedRemaining: nil)
        }
        fire()
    }
    #endif
}
