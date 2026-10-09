import AppKit
import SwiftUI

/// Renders the island straight to PNGs so layout can be checked without
/// screen-recording permission or a human staring at the menu bar.
///
///     NeoNotch.app/Contents/MacOS/NeoNotch --snapshot ~/Desktop/shots
@MainActor
enum Snapshotter {
    static let flag = "--snapshot"

    /// Returns the output directory when the process was launched to snapshot.
    static func requestedDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        ClockBridge.isEnabled = false
        TimerModel.remembersRecents = false
        NotesModel.connectsReminders = false
        let viewModel = NotchViewModel()
        viewModel.update(metrics: NotchMetrics(
            hasPhysicalNotch: false,
            collapsedSize: CGSize(width: 210, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1408, height: 881),
            menuBarHeight: 32
        ))

        write(viewModel, name: "01-collapsed-idle", to: directory)

        viewModel.open(tab: .shelf)
        write(viewModel, name: "05-shelf-empty", to: directory)
        viewModel.close()

        #if DEBUG
        viewModel.shelf.debugSeed()
        viewModel.clipboard.debugSeed()
        viewModel.music.debugSeed()
        viewModel.calendar.debugSeedSample()
        viewModel.notes.debugSeedSample()
        viewModel.bookmarks.debugUseStarters()
        viewModel.battery.debugSet(level: 30, charging: false)
        #endif

        write(viewModel, name: "02-collapsed-playing", to: directory)

        viewModel.flash("Copied", for: 999)
        write(viewModel, name: "03-collapsed-toast", to: directory)
        viewModel.clearToast()

        viewModel.timers.start(seconds: 305)
        write(viewModel, name: "04-collapsed-timer", to: directory)
        viewModel.timers.cancel()

        for tab in NotchTab.allCases {
            viewModel.open(tab: tab)
            write(viewModel, name: "10-open-\(tab.rawValue)", to: directory)
        }

        // Closed on Clipboard, a plain open still lands on Home.
        viewModel.open(tab: .clipboard)
        viewModel.close()
        viewModel.open()
        write(viewModel, name: "11-reopened-on-home", to: directory)

        // Two shots of a running stopwatch. If TimelineView is not driving in a
        // panel that never becomes key, these come out identical.
        viewModel.timers.toggleStopwatch()
        viewModel.open(tab: .timer)
        write(viewModel, name: "20-stopwatch-a", to: directory)
        write(viewModel, name: "20-stopwatch-b", to: directory)
        viewModel.timers.resetStopwatch()

        #if DEBUG
        // Every state the music tab can be in, not only the happy one.
        viewModel.open(tab: .music)
        viewModel.music.debugSeed(playing: false)
        write(viewModel, name: "30-music-paused", to: directory)
        viewModel.music.debugSeed(permission: .notDetermined)
        write(viewModel, name: "31-music-needs-permission", to: directory)
        viewModel.music.debugSeed(permission: .denied)
        write(viewModel, name: "32-music-denied", to: directory)
        viewModel.music.debugSeed(artwork: false)
        write(viewModel, name: "33-music-no-artwork", to: directory)
        viewModel.music.debugSeed(longTitle: true)
        write(viewModel, name: "34-music-long-title", to: directory)
        viewModel.music.debugApply(track: nil, playing: false, source: nil)
        write(viewModel, name: "35-music-idle", to: directory)

        viewModel.close()
        viewModel.music.debugSeed(longTitle: true)
        write(viewModel, name: "36-collapsed-long-title", to: directory)
        viewModel.music.debugSeed(playing: false)
        write(viewModel, name: "37-collapsed-paused", to: directory)
        viewModel.music.debugSeed()

        // The Home widgets in motion.
        viewModel.focus.debugStart(remaining: 18 * 60 + 42, sprint: 2)
        write(viewModel, name: "40-collapsed-focus", to: directory)
        viewModel.open(tab: .home)
        write(viewModel, name: "41-home-focus-running", to: directory)
        viewModel.focus.reset()
        viewModel.notes.beginNew()
        viewModel.notes.draft?.text = "Call the bank about the card before 5"
        write(viewModel, name: "42-home-note-editing", to: directory)
        viewModel.notes.discardDraft()
        // The editor's view clears this on its next update; a script closing
        // the panel straight after cannot wait for that.
        viewModel.setTextEntry(false)
        viewModel.close()
        viewModel.debugFlashCharging(level: 30)
        write(viewModel, name: "43-collapsed-charging", to: directory)

        // A finished timer rings in the closed notch; nothing opens or sticks.
        viewModel.timers.debugFire()
        write(viewModel, name: "44-collapsed-timer-done", to: directory)
        viewModel.timers.acknowledgeFire()

        // A timer and the stopwatch running in Apple Clock, followed here.
        viewModel.timers.clock.debugSet(
            timers: [ClockTimer(id: "clock-demo", title: "Tea", duration: 300,
                                endDate: Date().addingTimeInterval(222), pausedRemaining: nil)],
            stopwatch: ClockStopwatch(isRunning: true, baseElapsed: 0, since: Date().addingTimeInterval(-75))
        )
        write(viewModel, name: "45-collapsed-clock-timer", to: directory)
        viewModel.open(tab: .timer)
        write(viewModel, name: "46-open-timer-clock", to: directory)
        viewModel.timers.clock.debugSet(timers: [], stopwatch: nil)
        viewModel.close()
        write(viewModel, name: "47-collapsed-clock-cancelled", to: directory)
        #endif

        print("Wrote snapshots to \(directory.path)")
    }

    private static let canvasSize = CGSize(width: 1360, height: 300)

    /// Renders through a real `NSHostingView` in an offscreen window.
    ///
    /// `ImageRenderer` skips anything AppKit-backed — sliders, text fields and
    /// scroll view content come out as yellow placeholders or nothing at all —
    /// so it lies about exactly the parts worth checking.
    private static func write(_ viewModel: NotchViewModel, name: String, to directory: URL) {
        let canvas = ZStack(alignment: .top) {
            // Stand-in for the desktop so the black island is actually visible.
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.24, blue: 0.34),
                         Color(red: 0.40, green: 0.30, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Stand-in for the menu bar strip.
            Rectangle()
                .fill(Color.black.opacity(0.28))
                .frame(height: 32)
            NotchRootView(viewModel: viewModel)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)

        let frame = CGRect(origin: .zero, size: canvasSize)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingView(rootView: canvas)
        hosting.frame = frame
        window.contentView = hosting
        // Offscreen, but ordered in so AppKit actually lays out and draws it.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()

        // Let SwiftUI settle, thumbnails arrive and animations land.
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        hosting.layoutSubtreeIfNeeded()

        defer { window.orderOut(nil) }

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("Failed to allocate bitmap for \(name)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)

        guard let png = representation.representation(using: .png, properties: [:]) else {
            print("Failed to encode \(name)")
            return
        }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

#if DEBUG
extension ShelfModel {
    /// Files that exist on every Mac, so snapshots have real icons.
    func debugSeed() {
        let candidates = [
            "/System/Applications/Music.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Utilities/Terminal.app",
            "/etc/hosts"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            debugAppend(ShelfItem(
                url: url,
                isStaged: false,
                thumbnail: NSWorkspace.shared.icon(forFile: path)
            ))
        }
    }
}

extension ClipboardModel {
    func debugSeed() {
        debugReplace([
            ClipboardEntry(
                payload: .text("https://developer.apple.com/documentation/appkit/nspanel"),
                capturedAt: Date().addingTimeInterval(-30),
                sourceApp: "Safari",
                sourceIcon: nil,
                isPinned: true
            ),
            ClipboardEntry(
                payload: .text("withAnimation(.notchSpring) { viewModel.open() }"),
                capturedAt: Date().addingTimeInterval(-240),
                sourceApp: "Xcode",
                sourceIcon: nil
            ),
            ClipboardEntry(
                payload: .files([URL(fileURLWithPath: "/etc/hosts")]),
                capturedAt: Date().addingTimeInterval(-900),
                sourceApp: "Finder",
                sourceIcon: nil
            )
        ])
    }
}

extension CalendarModel {
    func debugSeedSample() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        debugSeed([
            CalendarEvent(id: "1", title: "Design review", start: at(10, 0), end: at(11, 0),
                          isAllDay: false, color: .systemPurple, location: "Studio"),
            CalendarEvent(id: "2", title: "Badminton practice", start: at(18, 0), end: at(19, 30),
                          isAllDay: false, color: .systemGreen, location: nil),
            CalendarEvent(id: "3", title: "Dinner at MyFresh", start: at(20, 0), end: at(21, 15),
                          isAllDay: false, color: .systemOrange, location: nil)
        ])
    }
}

extension NotesModel {
    func debugSeedSample() {
        let now = Date()
        debugSeed([
            Note(text: "\u{201C}Your future is created by what you do today.\u{201D}", color: .blue,
                 createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-600)),
            Note(text: "Grab the charger from the office", color: .red,
                 createdAt: now.addingTimeInterval(-3_600), updatedAt: now.addingTimeInterval(-3_600)),
            Note(text: "Ship the notch update", color: .green,
                 createdAt: now.addingTimeInterval(-7_200), updatedAt: now.addingTimeInterval(-7_200), isDone: true)
        ])
    }
}

extension MusicModel {
    func debugSeed(
        playing: Bool = true,
        permission: AutomationPermission = .granted,
        artwork: Bool = true,
        longTitle: Bool = false
    ) {
        debugApply(
            track: NowPlayingTrack(
                title: longTitle
                    ? "Midnight City (Eric Prydz Private Remix) — Extended Version"
                    : "Midnight City",
                artist: "M83",
                album: "Hurry Up, We're Dreaming",
                duration: 243,
                id: "spotify:track:debug"
            ),
            playing: playing,
            source: .spotify,
            position: 88,
            artwork: artwork ? Self.debugCover : nil,
            permission: permission
        )
    }

    /// A made-up cover — dusk gradient, sun, horizon — with enough colour to
    /// exercise the palette and the glow without shipping an image.
    static let debugCover = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
        NSGradient(colors: [
            NSColor(srgbRed: 0.98, green: 0.38, blue: 0.48, alpha: 1),
            NSColor(srgbRed: 0.45, green: 0.17, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.09, green: 0.06, blue: 0.22, alpha: 1)
        ])?.draw(in: rect, angle: -90)
        NSColor(srgbRed: 1, green: 0.8, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 95, y: 112, width: 110, height: 110)).fill()
        NSColor(srgbRed: 0.09, green: 0.06, blue: 0.22, alpha: 0.9).setFill()
        for band in 0..<6 {
            NSBezierPath(rect: NSRect(x: 0, y: 72 + CGFloat(band) * 10, width: rect.width, height: CGFloat(2 + band))).fill()
        }
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: rect.width, height: 74)).fill()
        return true
    }
}
#endif
