import AppKit
import Combine

/// A timer running or paused in Apple's Clock app.
struct ClockTimer: Equatable {
    let id: String
    let title: String
    let duration: TimeInterval
    /// When it goes off; nil while paused.
    let endDate: Date?
    /// Time left, while paused.
    let pausedRemaining: TimeInterval?
}

/// Clock's stopwatch, while it has time on it.
struct ClockStopwatch: Equatable {
    let isRunning: Bool
    /// Time on it at `since`; while running it counts on from there.
    let baseElapsed: TimeInterval
    let since: Date

    func elapsed(at date: Date) -> TimeInterval {
        isRunning ? baseElapsed + max(0, date.timeIntervalSince(since)) : baseElapsed
    }
}

/// Apple's Clock app, seen — and, through your shortcuts, driven — from the notch.
///
/// Seeing needs nothing. Clock keeps its timers and stopwatch with its daemon,
/// `mobiletimerd`, in a preferences domain any app of yours can read, so a
/// timer started in Clock is on the notch within a second.
///
/// Driving it is another matter. The daemon only talks to Apple-signed apps
/// and Clock has no AppleScript, but Shortcuts has Clock actions — Start Timer,
/// Cancel Timer, Start Stopwatch… NeoNotch runs those through shortcuts you
/// make once, found by name (`Command.shortcutName`) and run with
/// `/usr/bin/shortcuts`. Each one is optional: whatever exists is used, and
/// anything missing leaves NeoNotch's own timer and stopwatch in charge.
final class ClockBridge: ObservableObject {
    enum Command: String, CaseIterable, Identifiable {
        case startTimer, pauseTimer, resumeTimer, cancelTimer
        case startStopwatch, stopStopwatch, resetStopwatch

        var id: String { rawValue }

        /// The Clock action the shortcut holds, as Shortcuts names it.
        var clockAction: String {
            switch self {
            case .startTimer: "Start Timer"
            case .pauseTimer: "Pause Timer"
            case .resumeTimer: "Resume Timer"
            case .cancelTimer: "Cancel Timer"
            case .startStopwatch: "Start Stopwatch"
            case .stopStopwatch: "Stop Stopwatch"
            case .resetStopwatch: "Reset Stopwatch"
            }
        }

        /// What the shortcut must be called for NeoNotch to find it.
        var shortcutName: String { "NeoNotch " + clockAction }
    }

    /// Clock's timers that are running or paused, soonest to go off first.
    @Published private(set) var timers: [ClockTimer] = []
    @Published private(set) var stopwatch: ClockStopwatch?
    /// The shortcuts that exist, so NeoNotch knows what it can ask of Clock.
    @Published private(set) var installed: Set<Command> = []

    /// Told when a shortcut ran but failed, so the notch can say so.
    var onFailure: ((Command) -> Void)?

    private static let domain = "com.apple.mobiletimerd" as CFString
    private static let shortcutsTool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Off for snapshots, which start timers and a stopwatch of their own and
    /// must neither show your real ones nor start any in Clock.
    static var isEnabled = true

    private var poll: Timer?
    private var pollCount = 0
    /// Polled four times a second for a moment after a command, so its
    /// effect shows at once rather than on the next once-a-second pass.
    private var fastPollUntil = Date.distantPast
    private var lastShortcutsCheck = Date.distantPast

    init(live: Bool = ClockBridge.isEnabled) {
        guard live else { return }
        refresh()
        refreshShortcuts(force: true)
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollCount += 1
            if self.pollCount % 4 == 0 || Date() < self.fastPollUntil { self.refresh() }
        }
        poll?.tolerance = 0.1
    }

    deinit {
        poll?.invalidate()
    }

    // MARK: Reading Clock

    func refresh() {
        CFPreferencesAppSynchronize(Self.domain)
        let now = Date()
        let freshTimers = Self.timers(in: CFPreferencesCopyAppValue("MTTimers" as CFString, Self.domain), now: now)
        let freshStopwatch = Self.stopwatch(in: CFPreferencesCopyAppValue("MTStopwatches" as CFString, Self.domain))
        if freshTimers != timers {
            timers = freshTimers
            Trace.log("clock", "timers \(freshTimers)")
        }
        if freshStopwatch != stopwatch {
            stopwatch = freshStopwatch
            Trace.log("clock", "stopwatch \(String(describing: freshStopwatch)) raw \(Self.rawStopwatch() ?? [:])")
        }
    }

    /// MobileTimer's timer states. Only "stopped" has been seen on disk; the
    /// others follow its order.
    private static let stoppedState = 1
    private static let pausedState = 2
    private static let runningState = 3

    /// Clock's saved timers → the ones running or paused.
    ///
    /// Each is stored as `$MTTimer`, with its fire time as `$MTTimerDate` —
    /// when it goes off — while running, or `$MTTimerTimeInterval` — time
    /// left — otherwise. The values are found by type rather than by key, so a
    /// renamed key does not blind the notch.
    static func timers(in root: Any?, now: Date) -> [ClockTimer] {
        guard let root = root as? [String: Any], let list = root["MTTimers"] as? [Any] else { return [] }
        return list
            .compactMap { ($0 as? [String: Any])?["$MTTimer"] as? [String: Any] }
            .compactMap { timer(from: $0, now: now) }
            .sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    private static func timer(from saved: [String: Any], now: Date) -> ClockTimer? {
        let state = (saved["MTTimerState"] as? NSNumber)?.intValue ?? 0
        guard state != stoppedState else { return nil }
        let id = saved["MTTimerID"] as? String ?? ""
        let duration = (saved["MTTimerDuration"] as? NSNumber)?.doubleValue ?? 0
        let title = (saved["MTTimerTitle"] as? String) ?? ""
        let fireTime = saved["MTTimerFireTime"]

        var end = firstDate(in: fireTime)
        if end == nil, state == runningState, let left = firstNumber(in: fireTime) {
            // Running but saved as time left: count from when it was saved.
            end = (saved["MTTimerLastModifiedDate"] as? Date ?? now).addingTimeInterval(left)
        }
        if let end {
            // Already gone off: that alert is Clock's to ring.
            guard end > now else { return nil }
            return ClockTimer(id: id, title: title, duration: duration, endDate: end, pausedRemaining: nil)
        }
        if state == pausedState, let left = firstNumber(in: fireTime), left > 0 {
            return ClockTimer(id: id, title: title, duration: duration, endDate: nil, pausedRemaining: left)
        }
        return nil
    }

    /// Clock's stopwatch, or nil when it is reset.
    ///
    /// Its states are Reset, Running and Stopped — Clock's word for paused.
    /// Running is 1 whichever way the other two are numbered; a stopped one
    /// may keep its start date, so that alone does not mean running.
    static func stopwatch(in root: Any?) -> ClockStopwatch? {
        guard let saved = firstStopwatch(in: root) else { return nil }
        let state = (saved["MTStopwatchState"] as? NSNumber)?.intValue ?? 0
        let offset = (saved["MTStopwatchOffset"] as? NSNumber)?.doubleValue ?? 0
        let current = (saved["MTStopwatchCurrentInterval"] as? NSNumber)?.doubleValue ?? 0
        if state == 1, let start = saved["MTStopwatchStartDate"] as? Date {
            return ClockStopwatch(isRunning: true, baseElapsed: offset, since: start)
        }
        let time = current > 0 ? current : offset
        guard time > 0.001 else { return nil }
        return ClockStopwatch(isRunning: false, baseElapsed: time, since: .distantPast)
    }

    private static func firstStopwatch(in root: Any?) -> [String: Any]? {
        guard let root = root as? [String: Any], let list = root["MTStopwatches"] as? [Any] else { return nil }
        return (list.first as? [String: Any])?["$MTStopwatch"] as? [String: Any]
    }

    /// For the trace: what Clock saved, so the stopwatch reading can be checked.
    private static func rawStopwatch() -> [String: Any]? {
        guard Trace.isEnabled else { return nil }
        return firstStopwatch(in: CFPreferencesCopyAppValue("MTStopwatches" as CFString, domain))
    }

    private static func firstDate(in value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let dictionary = value as? [String: Any] { return dictionary.values.lazy.compactMap(firstDate).first }
        if let array = value as? [Any] { return array.lazy.compactMap(firstDate).first }
        return nil
    }

    private static func firstNumber(in value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.doubleValue }
        if let dictionary = value as? [String: Any] { return dictionary.values.lazy.compactMap(firstNumber).first }
        if let array = value as? [Any] { return array.lazy.compactMap(firstNumber).first }
        return nil
    }

    // MARK: Driving Clock

    func has(_ command: Command) -> Bool {
        installed.contains(command)
    }

    /// Looks up which of the shortcuts exist. A process launch, so throttled
    /// unless `force`.
    func refreshShortcuts(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastShortcutsCheck) > 10 else { return }
        lastShortcutsCheck = Date()
        DispatchQueue.global(qos: .utility).async {
            let names = Set(
                Self.runTool(["list"]).output
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            )
            let found = Set(Command.allCases.filter { names.contains($0.shortcutName.lowercased()) })
            DispatchQueue.main.async {
                if found != self.installed {
                    self.installed = found
                    Trace.log("clock", "shortcuts found: \(found.map(\.shortcutName).sorted())")
                }
            }
        }
    }

    /// Runs one of the shortcuts, in the background. False when it does not
    /// exist, so the caller can fall back to doing the job itself.
    @discardableResult
    func perform(_ command: Command, input: String? = nil) -> Bool {
        guard installed.contains(command) else { return false }
        fastPollUntil = Date().addingTimeInterval(4)
        DispatchQueue.global(qos: .userInitiated).async {
            var arguments = ["run", command.shortcutName]
            var inputFile: URL?
            if let input {
                // `shortcuts run` only takes input from a file.
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NeoNotch-clock-\(UUID().uuidString).txt")
                try? input.write(to: file, atomically: true, encoding: .utf8)
                inputFile = file
                arguments += ["--input-path", file.path]
            }
            let result = Self.runTool(arguments)
            inputFile.map { try? FileManager.default.removeItem(at: $0) }
            Trace.log("clock", "\(command.shortcutName) -> \(result.status) \(result.error)")
            DispatchQueue.main.async {
                self.refresh()
                if result.status != 0 { self.onFailure?(command) }
            }
        }
        return true
    }

    /// Tells the notch Clock never answered, for a command whose effect did
    /// not show up in Clock.
    func reportFailure(_ command: Command) {
        onFailure?(command)
    }

    #if DEBUG
    /// Stands in for Clock in snapshots. Never touches Clock's own data.
    func debugSet(timers: [ClockTimer], stopwatch: ClockStopwatch?) {
        self.timers = timers
        self.stopwatch = stopwatch
    }
    #endif

    func openClock() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app"))
    }

    /// Opens Shortcuts on a new, empty shortcut — the first step of making one.
    func openShortcuts() {
        if let url = URL(string: "shortcuts://create-shortcut"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
    }

    /// Runs `/usr/bin/shortcuts`, giving up after 20 s — a shortcut waiting on
    /// a dialog nobody sees must not hold a thread forever.
    private static func runTool(_ arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = shortcutsTool
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            if process.isRunning { process.terminate() }
        }
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
