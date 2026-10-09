import AppKit
import Combine
import SwiftUI

/// Owns the floating panel: keeps it glued to the top-centre of the active
/// screen, tracks the pointer so the island opens and closes on hover, and
/// republishes the hit-test region the panel uses for click-through.
final class NotchWindowController {
    let viewModel: NotchViewModel

    private var panel: NotchPanel?
    private var hostingView: PassthroughHostingView<NotchRootView>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pointerTimer: Timer?
    private var openWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private var fullScreenTimer: Timer?
    private var isHiddenForFullScreen = false
    private var cancellables = Set<AnyCancellable>()
    private var unlockObserver: ImmediateDistributedObserver?

    /// The panel is always this size; the island is drawn inside it and the rest
    /// is click-through. Sized to hold the widest island — Home with every
    /// widget on — plus room either side for its shadow.
    private static let panelSize = CGSize(width: 1320, height: 280)

    init(viewModel: NotchViewModel = NotchViewModel()) {
        self.viewModel = viewModel
    }

    // MARK: Lifecycle

    func start() {
        buildPanel()
        installMonitors()
        trace("started, tracing=\(Self.tracingEnabled), panel=\(panel?.frame.debugDescription ?? "nil")")
        runHitTestSelfCheck()
        runDropRegistrationCheck(when: "at launch")
        // SwiftUI registers drop targets during its first layout pass, so an
        // immediate check can report a false negative.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.runDropRegistrationCheck(when: "after layout")
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncInteractiveRect() }
            .store(in: &cancellables)

        // Width, height and the alignment nudge all change where the panel goes.
        viewModel.preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.reposition() }
            .store(in: &cancellables)

        installSessionObservers()
        installHotKey()
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func buildPanel() {
        let screen = NotchGeometry.preferredScreen() ?? NSScreen.screens[0]
        viewModel.update(metrics: NotchGeometry.metrics(for: screen, preferences: viewModel.preferences))

        let panel = NotchPanel(contentRect: frame(on: screen))
        let hosting = PassthroughHostingView(rootView: NotchRootView(viewModel: viewModel))
        hosting.frame = CGRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        hosting.onDragEntered = { [weak self] in
            guard let self else { return }
            self.viewModel.isDropTargeted = true
            // Open onto the shelf so the whole panel becomes the drop area
            // instead of the 210×30 strip the drag arrived on.
            withAnimation(.notchSnap) { self.viewModel.open(tab: .shelf) }
            self.syncInteractiveRect()
            self.trace("drag entered")
        }
        hosting.onDragExited = { [weak self] in
            self?.viewModel.isDropTargeted = false
            self?.viewModel.isAirDropTargeted = false
        }
        hosting.onDragMoved = { [weak self] point in
            guard let self else { return }
            let overAirDrop = self.viewModel.tab == .shelf && self.viewModel.airDropZone.contains(point)
            if self.viewModel.isAirDropTargeted != overAirDrop {
                withAnimation(.easeOut(duration: 0.15)) { self.viewModel.isAirDropTargeted = overAirDrop }
            }
        }
        hosting.onDrop = { [weak self] pasteboard, point in
            guard let self else { return false }
            self.viewModel.isDropTargeted = false
            self.viewModel.isAirDropTargeted = false

            // Dropped on the AirDrop zone: send it, don't shelve it.
            if self.viewModel.tab == .shelf, self.viewModel.airDropZone.contains(point) {
                let items = self.viewModel.shelf.sharingItems(from: pasteboard)
                let sent = AirDrop.send(items)
                self.trace("airdrop \(items.count) item(s): \(sent)")
                if !sent { self.viewModel.flash("AirDrop is off", style: .init(symbol: "exclamationmark.circle.fill", tint: .orange)) }
                return sent
            }

            return self.viewModel.shelf.accept(pasteboard: pasteboard) { [weak self] added in
                guard let self else { return }
                self.trace("dropped \(added) item(s)")
                if added > 0 { self.viewModel.flash("Added \(added) to shelf") }
            }
        }

        panel.onKeyChange = { [weak self] isKey in
            isKey ? self?.viewModel.panelDidBecomeKey() : self?.viewModel.panelDidResignKey()
        }
        // A note or an address field wants typing: take the keyboard without
        // activating the app, which is what a non-activating panel is for.
        viewModel.onRequestKeyFocus = { [weak panel] in
            panel?.makeKey()
        }

        panel.contentView = hosting

        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting
        syncInteractiveRect()
    }

    private func frame(on screen: NSScreen) -> CGRect {
        // Rounded so the panel never lands on a half point, which would put the
        // island half a pixel off centre on a 1x display.
        let centred = (screen.frame.midX - Self.panelSize.width / 2).rounded()
        return CGRect(
            x: centred + viewModel.preferences.horizontalOffset.rounded(),
            y: screen.frame.maxY - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
    }

    func reposition() {
        guard let panel else { return }
        let screen = NotchGeometry.preferredScreen() ?? NSScreen.screens[0]
        viewModel.update(metrics: NotchGeometry.metrics(for: screen, preferences: viewModel.preferences))
        panel.setFrame(frame(on: screen), display: true)
        syncInteractiveRect()
    }

    // MARK: Hit testing

    /// Island rect in window coordinates (bottom-left origin), anchored top-centre.
    private var islandRect: CGRect {
        let size = viewModel.islandSize
        return CGRect(
            x: (Self.panelSize.width - size.width) / 2,
            y: Self.panelSize.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Slightly generous version of `islandRect` used for pointer tracking and
    /// as a drop halo, so you do not have to hit the pill pixel-perfectly.
    private var hoverRect: CGRect {
        let pad = NotchViewModel.hoverPadding
        let rect = islandRect
        return CGRect(
            x: rect.minX - pad.left,
            y: rect.minY - pad.bottom,
            width: rect.width + pad.left + pad.right,
            height: rect.height + pad.bottom + pad.top
        )
    }

    private func syncInteractiveRect() {
        // Closed: only the pill itself is live, so clicks beside the notch reach
        // the menu bar. Open: the generous rect, so the panel is easy to stay
        // inside and easy to drop onto.
        hostingView?.interactiveRect = viewModel.state == .closed ? islandRect : hoverRect
        hostingView?.isClosed = viewModel.state == .closed
    }

    private static var tracingEnabled: Bool { Trace.isEnabled }

    private func trace(_ message: @autoclosure () -> String) {
        Trace.log("window", message())
    }

    private var pointerEventCount = 0

    /// Reports whether anything in the panel is actually registered as a drag
    /// destination. If SwiftUI's `onDrop` never reached AppKit, no amount of
    /// aiming at the notch will drop a file on it.
    private func runDropRegistrationCheck(when: String) {
        guard Trace.isEnabled, let content = panel?.contentView else { return }
        var found: [String] = []
        func walk(_ view: NSView) {
            if !view.registeredDraggedTypes.isEmpty {
                let types = view.registeredDraggedTypes.map(\.rawValue).joined(separator: " ")
                found.append("\(type(of: view)) frame=\(view.convert(view.bounds, to: nil)) types=[\(types)]")
            }
            view.subviews.forEach(walk)
        }
        walk(content)
        trace("drag destinations \(when), state=\(viewModel.state): "
            + (found.isEmpty ? "NONE REGISTERED" : found.joined(separator: " | ")))
    }

    /// Exercises the passthrough maths against the real view. A wrong coordinate
    /// space here would either swallow every click on the desktop behind the
    /// panel or make the island itself untappable, and neither is visible from
    /// the outside until you try to use the Mac.
    private func runHitTestSelfCheck() {
        guard Self.tracingEnabled, let view = hostingView else { return }
        let centre = CGPoint(x: hoverRect.midX, y: hoverRect.midY)
        let farCorner = CGPoint(x: 20, y: 20)
        let wasClosed = view.isClosed

        // Closed, nothing is clickable: the notch opens on hover, never on a
        // click, so a click near it must reach the menu bar underneath.
        view.isClosed = true
        trace("closed / island centre -> "
            + (view.hitTest(centre) == nil ? "nil (ok: clicks pass through)" : "view (BAD: swallows clicks)"))

        view.isClosed = false
        trace("open / island centre -> "
            + (view.hitTest(centre) == nil ? "nil (BAD: island is dead)" : "view (ok)"))
        trace("open / far corner -> "
            + (view.hitTest(farCorner) == nil ? "nil (ok: clicks pass through)" : "view (BAD: blocks desktop)"))

        view.isClosed = wasClosed
    }

    // MARK: Pointer tracking

    private func installMonitors() {
        // Polling `NSEvent.mouseLocation` is the primary signal: it is a couple
        // of float compares at 10 Hz and it keeps working in the cases where
        // move events never reach us — over another app's full-screen surface,
        // during a drag session, or when the pointer is warped rather than moved.
        // 20 Hz: during a drag this poll is the only signal we get, and 100 ms of
        // lag reads as the notch not noticing you. The per-tick work is two
        // float compares plus a button-state read; the pasteboard is only
        // consulted once a button is actually down.
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pointerMoved()
        }
        pointerTimer?.tolerance = 0.02

        fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateFullScreenVisibility()
        }
        fullScreenTimer?.tolerance = 0.5

        // Event monitors are the accelerator: when they do fire we react on the
        // very next event instead of waiting up to 100 ms for the next tick.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            self?.pointerMoved()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            self?.pointerMoved()
            return event
        }
    }

    // MARK: Keyboard shortcut

    private func installHotKey() {
        HotKeyCenter.shared.onPress = { [weak self] in
            guard let self else { return }
            withAnimation(.notchSnap) { self.viewModel.toggleFromShortcut() }
            self.syncInteractiveRect()
        }
        HotKeyCenter.shared.register(viewModel.preferences.toggleShortcut)
        viewModel.preferences.$toggleShortcut
            .removeDuplicates()
            .dropFirst()
            .sink { shortcut in HotKeyCenter.shared.register(shortcut) }
            .store(in: &cancellables)
    }

    // MARK: Lock, sleep and fast user switching

    /// Re-asserts the panel whenever the session comes back.
    ///
    /// NeoNotch cannot draw on the lock screen — macOS hides every user-session
    /// window behind `loginwindow` so that no app can put its own interface next
    /// to the password field. What it can do is be there again the instant you
    /// are back, rather than waiting for the next screen-parameters change.
    private func installSessionObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ] {
            workspace.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.reassert(reason: name.rawValue) }
                .store(in: &cancellables)
        }

        // Not `publisher(for:)`: AppKit would hold the unlock back until
        // NeoNotch was next activated. See `ImmediateDistributedObserver`.
        unlockObserver = ImmediateDistributedObserver(
            name: Notification.Name("com.apple.screenIsUnlocked")
        ) { [weak self] in
            self?.reassert(reason: "screenIsUnlocked")
        }
    }

    private func reassert(reason: String) {
        guard let panel else { return }
        isHiddenForFullScreen = false
        reposition()
        panel.orderFrontRegardless()
        trace("re-asserted after \(reason)")
    }

    // MARK: Full-screen deference

    /// A black island floating over full-screen video is just in the way, so
    /// step aside while something owns the whole display.
    private func updateFullScreenVisibility() {
        guard let panel else { return }
        // Never disappear mid-interaction.
        guard viewModel.state == .closed, !viewModel.holdsOpen else { return }

        let screen = NotchGeometry.preferredScreen() ?? NSScreen.screens[0]
        let shouldHide = Self.hasFullScreenWindow(covering: screen)
        guard shouldHide != isHiddenForFullScreen else { return }
        isHiddenForFullScreen = shouldHide

        if shouldHide {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        trace("full-screen \(shouldHide ? "detected, hiding" : "ended, showing")")
    }

    /// Looks for a normal-layer window as large as the display. Window bounds
    /// are readable without screen-recording permission; only titles are gated.
    private static func hasFullScreenWindow(covering screen: NSScreen) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }

        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            if width >= screen.frame.width - 1, height >= screen.frame.height - 1 {
                return true
            }
        }
        return false
    }

    /// Where an incoming drag counts as "heading for the notch": the whole top
    /// strip of the display, in screen coordinates.
    ///
    /// It was a 610 pt box centred on the notch, and a drag coming in from the
    /// right at x≈1100 sailed straight past it. Since this is only consulted
    /// while a drag is actually in flight, it can be as wide as the screen
    /// without ever swallowing an ordinary click.
    private var dropApproachRect: CGRect {
        let screen = viewModel.metrics.screenFrame != .zero
            ? viewModel.metrics.screenFrame
            : (NSScreen.main?.frame ?? .zero)
        return CGRect(
            x: screen.minX,
            y: screen.maxY - 200,
            width: screen.width,
            height: 200
        )
    }

    private func pointerMoved() {
        // The single place drag state advances; everything else reads the cache.
        NotchDragTypes.sample()
        guard let panel, !isHiddenForFullScreen else { return }
        let global = NSEvent.mouseLocation
        let local = CGPoint(x: global.x - panel.frame.minX, y: global.y - panel.frame.minY)

        // A drag heading our way wins over everything else: snap open onto the
        // Shelf immediately, whatever tab was last used and without waiting out
        // the hover delay. Returning early also stops the close logic from
        // fighting this while the pointer is still outside the panel proper.
        if NotchDragTypes.isDragInFlight, dropApproachRect.contains(global) {
            cancelClose()
            cancelOpen()
            if viewModel.state != .open || viewModel.tab != .shelf {
                withAnimation(.notchSnap) { viewModel.open(tab: .shelf) }
                syncInteractiveRect()
                trace("drag approaching -> shelf")
            }
            return
        }

        let inside = hoverRect.contains(local)

        pointerEventCount += 1
        if pointerEventCount % 20 == 1 {
            trace("pointer #\(pointerEventCount) local=\(local) inside=\(inside)")
        }

        if inside {
            cancelClose()
            if viewModel.state == .closed, viewModel.preferences.openOnHover {
                scheduleOpen()
            }
        } else {
            cancelOpen()
            if viewModel.state == .open, !viewModel.holdsOpen {
                scheduleClose()
            }
        }
    }

    private func scheduleOpen() {
        guard openWorkItem == nil else { return }

        let delay = viewModel.preferences.hoverOpenDelay
        guard delay > 0.005 else {
            // No dwell time: open on this very event rather than bouncing
            // through the run loop, so the panel is up on the same frame the
            // pointer arrives.
            performOpen()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.openWorkItem = nil
            self?.performOpen()
        }
        openWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performOpen() {
        withAnimation(.notchSnap) { viewModel.open() }
        syncInteractiveRect()
        trace("opened, hitRect=\(hoverRect)")
    }

    private func cancelOpen() {
        openWorkItem?.cancel()
        openWorkItem = nil
    }

    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWorkItem = nil
            withAnimation(.notchSpring) { self.viewModel.close() }
            self.syncInteractiveRect()
            self.trace("closed")
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func cancelClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }
}

extension Animation {
    /// One spring for every island transition, so open/close/resize feel related.
    static let notchSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)

    /// Faster variant for reacting to an incoming drag, where any perceptible
    /// wind-up reads as the notch failing to notice you.
    static let notchSnap = Animation.spring(response: 0.2, dampingFraction: 0.84)
}

/// Watches one distributed notification with `.deliverImmediately`, calling
/// `handler` on the main thread.
///
/// `publisher(for:)` registers with the default `.coalesce` behaviour, and
/// AppKit suspends that delivery from the moment the app resigns active until
/// it is next activated. The panel never activates NeoNotch, but a file picker
/// or AirDrop does, and from then on an unlock sat in that queue instead of
/// re-asserting the panel. Same reason, and the same shape, as
/// `PlayerBroadcastObserver`.
private final class ImmediateDistributedObserver: NSObject {
    private let handler: () -> Void

    init(name: Notification.Name, handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(received(_:)),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func received(_ note: Notification) {
        if Thread.isMainThread {
            handler()
        } else {
            DispatchQueue.main.async { self.handler() }
        }
    }
}
