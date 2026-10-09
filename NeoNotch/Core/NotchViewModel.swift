import AppKit
import Combine
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, music, timer, play, settings

    var id: String { rawValue }

    /// Tabs in the strip. Settings is deliberately absent: it is reached by
    /// clicking the gear, never by sliding the pointer across the strip.
    static var strip: [NotchTab] { allCases.filter { $0 != .settings } }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .music: "Music"
        case .timer: "Timer"
        case .play: "Play"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .music: "music.note"
        case .timer: "timer"
        case .play: "gamecontroller"
        case .settings: "gearshape"
        }
    }
}

enum NotchState: Equatable {
    /// Sitting in the menu bar, showing nothing (or a small live indicator).
    case closed
    /// Fully expanded panel.
    case open
}

/// Drives the island: what size it is right now, which tab is showing, and the
/// hover/drag bookkeeping that decides when to open and close.
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .closed
    @Published var tab: NotchTab = .home
    @Published private(set) var metrics: NotchMetrics = .zero
    /// True while a drag is hovering the island, so the shelf can highlight.
    @Published var isDropTargeted = false
    /// True while a drag hovers the Shelf's AirDrop zone in particular.
    @Published var isAirDropTargeted = false
    /// Where the AirDrop zone is, in the hosting view's coordinates. Reported
    /// by `ShelfView`; deliberately not published — it only answers "did the
    /// drop land here", and publishing it would redraw the panel on layout.
    var airDropZone: CGRect = .zero
    /// Keeps the panel open even after the pointer leaves.
    @Published var isPinned = false

    /// A short-lived message shown in the collapsed pill, e.g. "Copied".
    @Published private(set) var toast: String?
    /// Tint and symbol for the toast; the default is a green tick.
    private var toastStyle = ToastStyle.success

    /// Something in the panel is taking typing — a note, a bookmark address.
    /// The panel holds the keyboard and stays open until it is done.
    @Published private(set) var isEditingText = false
    /// Checked when the panel opens rather than on every redraw.
    @Published private(set) var isAIAvailable = AIAssistant.isAvailable
    /// The charger just went in: shown in the closed notch for a moment.
    @Published private(set) var chargingFlash: Int?

    /// Set by the window controller: make the panel key so a text field in it
    /// receives typing without the app stealing focus from anything else.
    var onRequestKeyFocus: (() -> Void)?

    let preferences: Preferences

    // Feature models, owned here so they survive panel rebuilds.
    let shelf = ShelfModel()
    let clipboard = ClipboardModel()
    let music = MusicModel()
    let timers = TimerModel()
    let calendar = CalendarModel()
    let notes = NotesModel()
    let appleNotes = AppleNotesComposer()
    let focus = FocusModel()
    let bookmarks = BookmarksModel()
    let mirror = MirrorModel()
    let battery = BatteryModel()

    private var toastWorkItem: DispatchWorkItem?
    private var chargingWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Default size of the expanded panel. Tabs that need more room override
    /// the height in `expandedSize`.
    static let baseExpandedSize = CGSize(width: 580, height: 196)
    /// Padding around the island that still counts as "on the notch".
    ///
    /// The top inset matters more than it looks: the island's top edge is the
    /// screen's top edge, and `CGRect.contains` treats maxY as exclusive, so
    /// without it the very row of pixels the pointer lands on when you throw it
    /// at the top of the screen is the one row that does not register.
    static let hoverPadding = NSEdgeInsets(top: 8, left: 10, bottom: 14, right: 10)

    init(preferences: Preferences = .shared) {
        self.preferences = preferences

        // Re-publish nested model changes so SwiftUI redraws the island.
        for model in [shelf.objectWillChange.eraseToAnyPublisher(),
                      clipboard.objectWillChange.eraseToAnyPublisher(),
                      music.objectWillChange.eraseToAnyPublisher(),
                      timers.objectWillChange.eraseToAnyPublisher(),
                      calendar.objectWillChange.eraseToAnyPublisher(),
                      notes.objectWillChange.eraseToAnyPublisher(),
                      appleNotes.objectWillChange.eraseToAnyPublisher(),
                      focus.objectWillChange.eraseToAnyPublisher(),
                      bookmarks.objectWillChange.eraseToAnyPublisher(),
                      mirror.objectWillChange.eraseToAnyPublisher(),
                      battery.objectWillChange.eraseToAnyPublisher()] {
            model
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        focus.onPhaseEnd = { [weak self] finished, next in
            self?.focusPhaseEnded(finished, next: next)
        }
        battery.onEvent = { [weak self] event in
            self?.batteryEvent(event)
        }
        timers.clock.onFailure = { [weak self] _ in
            self?.flash("Clock didn't answer", style: ToastStyle(symbol: "exclamationmark.circle.fill", tint: .orange), for: 2.5)
        }
        appleNotes.onSaved = { [weak self] in
            self?.flash("Saved to Notes", style: ToastStyle(symbol: "note.text", tint: .yellow))
        }
    }

    // MARK: Geometry

    func update(metrics: NotchMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
    }

    /// Size of the island for the current state.
    var islandSize: CGSize {
        switch state {
        case .closed: collapsedSize
        case .open: expandedSize
        }
    }

    /// Size of the open panel.
    ///
    /// Every tab shares one width. Hovering a tab switches to
    /// it, so a panel that changed width per tab would slide the tab strip out
    /// from under the pointer — and the pointer would land on another tab and
    /// switch again. One width keeps the strip still. Tabs that do not want
    /// all of it centre their content instead.
    var expandedSize: CGSize {
        CGSize(
            width: panelWidth,
            height: Self.tallTabs.contains(tab) ? Self.tallExpandedHeight : Self.baseExpandedSize.height
        )
    }

    /// Settings, and Timer — laid out like Apple's Clock, with its Recents
    /// list and countdown ring — get the taller panel.
    static let tallTabs: Set<NotchTab> = [.settings, .timer]
    static let tallExpandedHeight: CGFloat = 268

    var panelWidth: CGFloat {
        Self.evenWidth(max(Self.minimumPanelWidth, homeWidth))
    }

    static let minimumPanelWidth: CGFloat = 640

    /// Home is exactly as wide as the widgets switched on:
    /// the row plus the panel's own 14 pt inset on either side.
    var homeWidth: CGFloat {
        let row = HomeModule.rowWidth(preferences.homeModules)
        guard row > 0 else { return Self.baseExpandedSize.width }
        return Self.evenWidth(min(max(row + 28, 480), Self.maxExpandedWidth))
    }

    /// The widest the panel ever gets; the window is sized to hold it.
    static let maxExpandedWidth: CGFloat = 1240

    /// What the closed island is currently showing, if anything. Single source
    /// of truth: `CollapsedView` draws it and `collapsedSize` measures it, so
    /// the pill can never be a different width than its contents need.
    struct CollapsedIndicator: Equatable {
        var symbol: String
        var text: String
        var tint: Color
        var showsAudioBars: Bool
        /// 0…1, drawn as a ring in the trailing gutter. Balances the leading
        /// icon so the pill is symmetric by weight and not only by geometry.
        var progress: Double?
        /// The album cover, drawn in the leading gutter in place of the symbol.
        var artwork: NSImage? = nil
        /// Bars move while music plays and lie flat while it is paused.
        var isAnimating = true

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.symbol == rhs.symbol
                && lhs.text == rhs.text
                && lhs.tint == rhs.tint
                && lhs.showsAudioBars == rhs.showsAudioBars
                && lhs.progress == rhs.progress
                && lhs.artwork === rhs.artwork
                && lhs.isAnimating == rhs.isAnimating
        }
    }

    /// Width of each side slot in the busy island: the icon or cover on the
    /// left, and its mirror (bars, ring) on the right.
    static let collapsedGutter: CGFloat = 18

    var collapsedIndicator: CollapsedIndicator? {
        if let toast {
            return CollapsedIndicator(
                symbol: toastStyle.symbol,
                text: toast,
                tint: toastStyle.tint,
                showsAudioBars: false,
                progress: nil
            )
        }
        if timers.didFire {
            // The small ring: a full circle for a few seconds, then idle.
            return CollapsedIndicator(
                symbol: "bell.fill",
                text: "Time's up",
                tint: .orange,
                showsAudioBars: false,
                progress: 1
            )
        }
        if timers.hasRunningTimer, let active = timers.active {
            return CollapsedIndicator(
                symbol: "timer",
                text: active.remainingLabel,
                tint: .orange,
                showsAudioBars: false,
                progress: active.progress()
            )
        }
        if focus.isRunning {
            return CollapsedIndicator(
                symbol: focus.phase.symbol,
                text: NotchCountdown.format(focus.remaining()),
                tint: focus.phase.tint,
                showsAudioBars: false,
                progress: focus.progress()
            )
        }
        if timers.isStopwatchRunning {
            // Whole seconds only: the closed island redraws the entire notch,
            // and hundredths up here would mean doing that 100 times a second
            // for something you are not reading that precisely anyway.
            return CollapsedIndicator(
                symbol: "stopwatch",
                text: NotchCountdown.format(timers.stopwatchElapsed()),
                tint: .cyan,
                showsAudioBars: false,
                progress: nil
            )
        }
        if let level = chargingFlash {
            return CollapsedIndicator(
                symbol: "bolt.fill",
                text: "\(level)%",
                tint: Self.chargingGreen,
                showsAudioBars: false,
                // The ring doubles as a battery gauge.
                progress: Double(level) / 100
            )
        }
        // `isLive` rather than `isPlaying`: it lingers briefly after a pause,
        // so skipping a track does not make the island jump in and out.
        if music.isLive, let track = music.track {
            return CollapsedIndicator(
                symbol: "music.note",
                text: track.title.isEmpty ? (music.source?.displayName ?? "Playing") : track.title,
                tint: music.palette.accentColor,
                showsAudioBars: true,
                progress: nil,
                artwork: music.artwork,
                isAnimating: music.isPlaying
            )
        }
        return nil
    }

    /// True while a timer, stopwatch or playback is live — the island takes on
    /// its bigger "busy" shape.
    var isBusy: Bool { collapsedIndicator != nil }

    /// Font the busy island draws its headline in. Shared with the width
    /// measurement so the pill is never narrower than the text inside it.
    static let busyFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    /// The closed island: a plain strip when idle, a wider one when busy.
    ///
    /// It grows **sideways only** and always stays exactly menu bar height, so
    /// it never reaches down into the window you are working in. That means it
    /// covers menu items instead — macOS lays the menu bar out with no idea the
    /// island exists — which is the accepted trade here.
    ///
    /// The tabbed panel is the exception: opening it does drop below the menu
    /// bar, because at that point you are looking at the panel, not past it.
    var collapsedSize: CGSize {
        var base = metrics.collapsedSize
        if base == .zero { base = CGSize(width: 210, height: 32) }

        guard let indicator = collapsedIndicator else {
            return CGSize(width: Self.evenWidth(base.width), height: base.height)
        }

        // Grow past the configured width only if the text genuinely needs it.
        let needed = Self.width(for: indicator)
        let width = max(preferences.busyWidth, min(needed, preferences.busyWidth + 120))
        return CGSize(
            width: Self.evenWidth(max(width, base.width)),
            height: base.height
        )
    }

    /// Measured, not guessed — the label is drawn with this exact font, and the
    /// icon is mirrored by an equal gutter on the right so the headline lands
    /// dead centre. See `CollapsedView`.
    private static func width(for indicator: CollapsedIndicator) -> CGFloat {
        let horizontalPadding: CGFloat = 12 * 2
        let gutter: CGFloat = (collapsedGutter + 8) * 2   // icon + spacing, mirrored
        let textWidth = (indicator.text as NSString)
            .size(withAttributes: [.font: busyFont])
            .width
            .rounded(.up)
        return horizontalPadding + gutter + textWidth
    }

    /// Even widths centre on whole points inside an even-width panel, so the
    /// island never lands on a half-point and never leans one way.
    static func evenWidth(_ width: CGFloat) -> CGFloat {
        max(2, (width / 2).rounded() * 2)
    }

    // MARK: State transitions

    /// Opens the panel on Home — by hover, the keyboard shortcut or the menu,
    /// never on whichever tab happened to be showing when it last closed.
    /// `requested` is for the few openings that have somewhere specific to be,
    /// such as a file dragged in going to the Shelf.
    func open(tab requested: NotchTab? = nil) {
        if let requested {
            tab = requested
        } else if state == .closed {
            tab = .home
        }
        guard state != .open else { return }
        isAIAvailable = AIAssistant.isAvailable
        state = .open
    }

    /// The keyboard shortcut. Opens pinned — the pointer is probably nowhere
    /// near the notch, and hover logic would close it again at once — and a
    /// second press closes it.
    func toggleFromShortcut() {
        if state == .open {
            isPinned = false
            isEditingText = false
            state = .closed
        } else {
            isPinned = true
            open()
        }
    }

    /// Reasons the panel must stay open no matter where the pointer is.
    ///
    /// A finished timer deliberately does not count. It used to, and the panel
    /// then sat stuck over your work until you found its Dismiss button; now it
    /// rings in the closed notch instead (see `collapsedIndicator`).
    var holdsOpen: Bool {
        isPinned || isDropTargeted || isEditingText
    }

    func close() {
        guard state == .open, !holdsOpen else { return }
        state = .closed
        isDropTargeted = false
        if tab == .settings {
            tab = tabBeforeSettings ?? .home
            tabBeforeSettings = nil
        }
    }

    func toggle() {
        if state == .open {
            isPinned = false
            state = .closed
        } else {
            open()
        }
    }

    /// A tab clicked, or rested on, in the strip. Not remembered: the next
    /// open starts on Home again.
    func select(_ tab: NotchTab) {
        guard self.tab != tab else { return }
        self.tab = tab
    }

    /// Where to return when leaving settings.
    private var tabBeforeSettings: NotchTab?

    var isShowingSettings: Bool { tab == .settings }

    /// Settings is a click-only mode, toggled by the gear. It never persists as
    /// the startup tab, and closing the panel drops back out of it, so you never
    /// reopen the notch into a settings screen you did not ask for.
    func toggleSettings() {
        if tab == .settings {
            tab = tabBeforeSettings ?? .home
            tabBeforeSettings = nil
        } else {
            tabBeforeSettings = tab
            tab = .settings
        }
    }

    // MARK: Toast

    func clearToast() {
        toastWorkItem?.cancel()
        toastWorkItem = nil
        toast = nil
    }

    struct ToastStyle {
        var symbol: String
        var tint: Color

        static let success = ToastStyle(symbol: "checkmark.circle.fill", tint: .green)
    }

    static let chargingGreen = Color(red: 0.2, green: 0.85, blue: 0.4)

    func flash(_ message: String, style: ToastStyle = .success, for duration: TimeInterval = 1.6) {
        toastWorkItem?.cancel()
        toastStyle = style
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toast = message
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self?.toast = nil
            }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: Typing

    /// A note or address field opened (true) or closed (false).
    func setTextEntry(_ active: Bool) {
        guard isEditingText != active else { return }
        isEditingText = active
        if active { onRequestKeyFocus?() }
    }

    /// You clicked back into a note that was left open.
    func panelDidBecomeKey() {
        if notes.draft != nil, !isEditingText { isEditingText = true }
    }

    /// You clicked into another app: stop holding the panel open. What you
    /// were typing stays in its draft.
    func panelDidResignKey() {
        if isEditingText { isEditingText = false }
    }

    #if DEBUG
    func debugFlashCharging(level: Int) {
        chargingFlash = level
    }
    #endif

    // MARK: Focus and battery

    private func focusPhaseEnded(_ finished: FocusModel.Phase, next: FocusModel.Phase) {
        if preferences.focusSound {
            NSSound(named: finished == .focus ? "Hero" : "Glass")?.play()
        }
        let minutes = Int(focus.duration / 60)
        let headline: String
        let body: String
        if finished == .focus {
            headline = next == .longBreak ? "Focus done · long break" : "Focus done · break"
            body = "Nice work. Take \(minutes) minutes."
        } else {
            headline = "Break over · focus"
            body = "Back to it — session \(focus.sprint) of \(focus.sprints)."
        }
        flash(headline, style: ToastStyle(symbol: next.symbol, tint: next.tint), for: 3)
        TimerNotifier.post(title: finished == .focus ? "Focus session done" : "Break over", body: body)
    }

    private func batteryEvent(_ event: BatteryModel.Event) {
        guard preferences.batteryAlerts else { return }
        switch event {
        case .pluggedIn(let level):
            chargingWorkItem?.cancel()
            withAnimation(.notchSpring) { chargingFlash = level }
            let work = DispatchWorkItem { [weak self] in
                withAnimation(.notchSpring) { self?.chargingFlash = nil }
            }
            chargingWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        case .low(let level):
            flash("Battery \(level)%", style: ToastStyle(symbol: "battery.25percent", tint: .red), for: 4)
        }
    }
}
