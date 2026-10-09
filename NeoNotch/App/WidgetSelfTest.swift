import AppKit

/// Exercises the logic behind the Home widgets without touching your
/// data: every model here writes into a throwaway folder.
///
///     NeoNotch.app/Contents/MacOS/NeoNotch --selftest-widgets
@MainActor
enum WidgetSelfTest {
    static let flag = "--selftest-widgets"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func run() -> Int32 {
        var failures = 0
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoNotch-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        Storage.overrideDirectory = sandbox
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // 1. Home layout: the row is exactly as wide as its widgets.
        let all = HomeModule.allCases
        let expected = all.reduce(0) { $0 + $1.width + 24 } + CGFloat(all.count - 1)
        report("home row width adds up", ok: HomeModule.rowWidth(all) == expected,
               detail: "\(HomeModule.rowWidth(all)) pt", &failures)
        let calendarOffset = HomeModule.offset(of: .calendar, in: [.music, .calendar])
        report("home offsets account for padding and the divider",
               ok: calendarOffset == HomeModule.music.width + 24 + 1,
               detail: "\(calendarOffset ?? -1) pt", &failures)

        // 2. Pomodoro: short breaks between sessions, a long one to end the
        //    cycle, then back to session one. Skips never count.
        let focus = FocusModel()
        let sprints = focus.sprints
        var phases: [String] = []
        for _ in 0..<(sprints * 2) {
            phases.append("\(focus.phase.rawValue)\(focus.phase == .focus ? "\(focus.sprint)" : "")")
            focus.skip()
        }
        let expectedPhases = (1...sprints).flatMap { sprint in
            ["focus\(sprint)", sprint == sprints ? "longBreak" : "shortBreak"]
        }
        report("focus cycle runs \(sprints) sessions, then a long break",
               ok: phases == expectedPhases && focus.phase == .focus && focus.sprint == 1,
               detail: phases.joined(separator: " → "), &failures)
        report("skipped sessions are not counted", ok: focus.completedToday == 0,
               detail: "\(focus.completedToday) today", &failures)

        // 3. Streak: consecutive days, with today counting only once it has a session.
        let calendar = Calendar.current
        let today = Date()
        func day(_ offset: Int) -> String {
            FocusModel.key(for: calendar.date(byAdding: .day, value: offset, to: today) ?? today)
        }
        let running = FocusModel.streak(in: [day(0): 2, day(-1): 1, day(-2): 4, day(-4): 1], today: today)
        let morning = FocusModel.streak(in: [day(-1): 1, day(-2): 1], today: today)
        let broken = FocusModel.streak(in: [day(-2): 3], today: today)
        report("streak counts consecutive days", ok: running == 3, detail: "\(running)", &failures)
        report("streak survives a morning with no session yet", ok: morning == 2, detail: "\(morning)", &failures)
        report("a gap breaks the streak", ok: broken == 0, detail: "\(broken)", &failures)

        // 4. Bookmarks: what the add field accepts, and how sites are named.
        let parsed: [(String, String?, String?)] = [
            ("github.com", BookmarksModel.webURL(from: "github.com")?.absoluteString, "https://github.com"),
            ("full URL", BookmarksModel.webURL(from: "https://www.youtube.com/feed")?.absoluteString, "https://www.youtube.com/feed"),
            ("plain words", BookmarksModel.webURL(from: "not a site")?.absoluteString, nil),
            ("no dot", BookmarksModel.webURL(from: "localhost")?.absoluteString, nil),
            ("other scheme", BookmarksModel.webURL(from: "ftp://example.com")?.absoluteString, nil)
        ]
        for (label, got, want) in parsed {
            report("bookmark input: \(label)", ok: got == want, detail: got ?? "rejected", &failures)
        }
        let name = BookmarksModel.name(for: URL(string: "https://www.github.com")!)
        report("bookmark name from address", ok: name == "Github", detail: name, &failures)

        let html = """
        <head><link rel="icon" href="/favicon-32.png" sizes="32x32">
        <link rel='apple-touch-icon' href='/touch.png'>
        <link rel="icon" href="https://cdn.example.com/icon-192.png" sizes="192x192">
        <link rel="mask-icon" href="/mask.svg"><link rel="stylesheet" href="/site.css"></head>
        """
        let icons = BookmarksModel.declaredIcons(in: html, base: URL(string: "https://example.com/home")!)
            .map(\.absoluteString)
        report("site icons: touch icon first, then biggest, no mask or svg",
               ok: icons == ["https://example.com/touch.png", "https://cdn.example.com/icon-192.png",
                             "https://example.com/favicon-32.png"],
               detail: icons.joined(separator: ", "), &failures)

        // 5. Bookmarks model: starters on first run, no duplicates, removal.
        let bookmarks = BookmarksModel()
        let starters = bookmarks.bookmarks.count
        bookmarks.add("github.com/")
        let afterDuplicate = bookmarks.bookmarks.count
        bookmarks.add("apple.com")
        let added = bookmarks.bookmarks.last
        if let added { bookmarks.remove(added) }
        report("bookmarks: starters, no duplicate, add and remove",
               ok: starters == BookmarksModel.starters.count && afterDuplicate == starters
                   && added?.name == "Apple" && bookmarks.bookmarks.count == starters,
               detail: "\(starters) starters, then \(bookmarks.bookmarks.count)", &failures)

        // 6. Notes: a draft becomes a note; emptying a note deletes it.
        let notes = NotesModel(syncsReminders: false)
        notes.beginNew()
        notes.draft?.text = "  Buy milk  "
        notes.draft?.color = .green
        notes.commitDraft()
        let saved = notes.notes.first
        if let saved {
            notes.beginEditing(saved)
            notes.draft?.text = "   "
            notes.commitDraft()
        }
        report("notes: save trims, empty edit deletes",
               ok: saved?.text == "Buy milk" && saved?.color == .green && notes.notes.isEmpty,
               detail: "saved \"\(saved?.text ?? "-")\", then \(notes.notes.count) notes", &failures)
        let reloaded = NotesModel(syncsReminders: false)
        report("notes persist to disk", ok: reloaded.notes.isEmpty, detail: "\(reloaded.notes.count) after reload", &failures)

        // 7. Runner: a jump goes up and comes back down.
        let runner = RunnerGame()
        runner.size = CGSize(width: 480, height: 140)
        runner.jump() // starts the round
        var time: TimeInterval = 1_000
        runner.step(to: time)
        runner.jump()
        var peak: CGFloat = 0
        for _ in 0..<60 {
            time += 1.0 / 60
            runner.step(to: time)
            peak = max(peak, runner.playerLift)
        }
        report("runner jump rises and lands", ok: peak > 60 && runner.playerLift == 0,
               detail: String(format: "peak %.0f pt", peak), &failures)

        // 8. Apple Clock: its saved state, shaped the way mobiletimerd writes it.
        let now = Date()
        func savedTimer(_ id: String, state: Int, fire: [String: Any], title: String = "") -> [String: Any] {
            ["$MTTimer": ["MTTimerID": id, "MTTimerState": state, "MTTimerDuration": 300,
                          "MTTimerTitle": title, "MTTimerFireTime": fire]]
        }
        let clockSaved: [String: Any] = ["MTTimers": [
            savedTimer("stopped", state: 1, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 300]]),
            savedTimer("later", state: 3, fire: ["$MTTimerDate": ["MTTimerDate": now.addingTimeInterval(600)]]),
            savedTimer("tea", state: 3, fire: ["$MTTimerDate": ["MTTimerDate": now.addingTimeInterval(120)]], title: "Tea"),
            savedTimer("paused", state: 2, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 90]]),
            savedTimer("rang", state: 3, fire: ["$MTTimerDate": ["MTTimerDate": now.addingTimeInterval(-5)]])
        ]]
        let clockTimers = ClockBridge.timers(in: clockSaved, now: now)
        report("clock: running timers first, paused kept, stopped and finished dropped",
               ok: clockTimers.map(\.id) == ["tea", "later", "paused"]
                   && clockTimers.first?.title == "Tea"
                   && abs((clockTimers.first?.endDate ?? now).timeIntervalSince(now) - 120) < 0.01
                   && clockTimers.last?.pausedRemaining == 90,
               detail: clockTimers.map(\.id).joined(separator: ", "), &failures)

        func savedStopwatch(state: Int, start: Date?, offset: Double, current: Double) -> [String: Any] {
            var fields: [String: Any] = ["MTStopwatchState": state, "MTStopwatchOffset": offset,
                                         "MTStopwatchCurrentInterval": current, "MTStopwatchLaps": []]
            if let start { fields["MTStopwatchStartDate"] = start }
            return ["MTStopwatches": [["$MTStopwatch": fields]]]
        }
        let runningWatch = ClockBridge.stopwatch(in: savedStopwatch(state: 1, start: now.addingTimeInterval(-30), offset: 0, current: 0))
        let pausedWatch = ClockBridge.stopwatch(in: savedStopwatch(state: 2, start: nil, offset: 0, current: 42.5))
        let resetWatch = ClockBridge.stopwatch(in: savedStopwatch(state: 0, start: nil, offset: 0, current: 0))
        // Stopped with its old start date still saved: paused, not counting.
        let stoppedWatch = ClockBridge.stopwatch(in: savedStopwatch(state: 2, start: now.addingTimeInterval(-100), offset: 0, current: 42.5))
        report("clock: stopwatch running, paused and reset",
               ok: runningWatch?.isRunning == true && abs((runningWatch?.elapsed(at: now) ?? 0) - 30) < 0.01
                   && pausedWatch?.isRunning == false && pausedWatch?.elapsed(at: now) == 42.5 && resetWatch == nil
                   && stoppedWatch?.isRunning == false && stoppedWatch?.elapsed(at: now) == 42.5,
               detail: String(format: "running %.1fs, paused %.1fs, reset %@",
                              runningWatch?.elapsed(at: now) ?? -1, pausedWatch?.elapsed(at: now) ?? -1,
                              resetWatch == nil ? "empty" : "not empty"), &failures)

        // What Clock has right now, read-only.
        let domain = "com.apple.mobiletimerd" as CFString
        CFPreferencesAppSynchronize(domain)
        let liveTimers = ClockBridge.timers(in: CFPreferencesCopyAppValue("MTTimers" as CFString, domain), now: now)
        let liveStopwatch = ClockBridge.stopwatch(in: CFPreferencesCopyAppValue("MTStopwatches" as CFString, domain))
        print("  [info] Apple Clock now — \(liveTimers.count) timer(s) running or paused; stopwatch "
              + (liveStopwatch.map { $0.isRunning ? "running" : "paused" } ?? "reset"))

        // 9. Apple Notes: whatever is typed makes a script that still compiles —
        //    quotes, backslashes and markup cannot break out of the note.
        let typed = "Call \"Mom\" \\ back\n<b>milk & eggs</b>\n\n\"end\""
        let notesScript = AppleNotesComposer.script(for: typed)
        let compileError = AppleScriptRunner.compileError(notesScript)
        report("notes app: typed text stays inside the note",
               ok: compileError == nil && notesScript.contains("&lt;b&gt;milk &amp; eggs&lt;/b&gt;"),
               detail: compileError ?? "compiles against Notes' dictionary", &failures)

        // 10. Apple Intelligence, for the record.
        print("  [info] Apple Intelligence — \(AIAssistant.availability)")

        print(failures == 0 ? "widget self-test PASSED" : "widget self-test FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    private static func report(_ name: String, ok: Bool, detail: String, _ failures: inout Int) {
        print("  [\(ok ? "pass" : "FAIL")] \(name) — \(detail)")
        if !ok { failures += 1 }
    }
}
