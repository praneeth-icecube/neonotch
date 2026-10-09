import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Above the menu bar (24) and status items (25) — but it must stay
        // *below* the dragging window level (500), because a window above the
        // drag layer is never offered as a drop destination. At `.screenSaver`
        // (1000) the panel drew fine and hit-tested fine for the mouse, while
        // AppKit silently never asked it about a single drag.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        // Never steal focus from whatever the user is actually working in.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    /// True when the panel takes the keyboard, false when it gives it up —
    /// so a note being typed can hold the notch open, and let go of it when
    /// you click into another app.
    var onKeyChange: ((Bool) -> Void)?

    override func becomeKey() {
        super.becomeKey()
        onKeyChange?(true)
    }

    override func resignKey() {
        super.resignKey()
        onKeyChange?(false)
    }
}

/// What the notch will take as a drop.
///
/// Declared here rather than through SwiftUI's `onDrop`, which normalises the
/// list it is given: asking for `[.fileURL, .image, .pdf, .text, .url, .item]`
/// registered only `public.data` and `public.item` with AppKit, so
/// `public.file-url` — the type Finder actually puts on the pasteboard when you
/// drag a file — was never registered and the notch silently refused every file.
enum NotchDragTypes {
    static let accepted: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .tiff, .png, .pdf, .rtf, .html, .fileContents
    ]

    /// Change count of the drag pasteboard while no button is held. Refreshed
    /// continuously by the pointer poll, so it always reflects "before the
    /// current gesture started".
    private static var idleChangeCount = -1

    /// True when a drag is in flight right now carrying something we accept.
    ///
    /// There is no public "is a drag happening anywhere" API, so this infers it.
    /// The obvious inference — button held, and the drag pasteboard offers a
    /// type we want — is wrong: **the drag pasteboard keeps its contents after
    /// the drag ends**, so once anything had ever been dragged, every ordinary
    /// click looked like a file drag and the notch flew open on the Shelf.
    ///
    /// What actually distinguishes a drag is that the pasteboard is *rewritten*
    /// when one begins. So the baseline change count is captured whenever no
    /// button is down, and a drag is only in flight once that count moves while
    /// a button is held.
    private static var cachedInFlight = false

    /// Last sampled answer. Cheap, and — more importantly — stable: `hitTest`
    /// can ask this as often as AppKit likes without perturbing the state
    /// machine that produces it.
    static var isDragInFlight: Bool { cachedInFlight }

    /// Called only by the pointer poll, so the baseline advances on a known
    /// clock. Sampling from `hitTest` as well used to let a single reading
    /// taken mid-drag overwrite the baseline with the drag's own change count,
    /// after which that drag could never be recognised again.
    static func sample() {
        let pasteboard = NSPasteboard(name: .drag)
        let buttonDown = NSEvent.pressedMouseButtons & 0x1 != 0
        if !buttonDown { idleChangeCount = pasteboard.changeCount }
        cachedInFlight = dragInFlight(
            buttonDown: buttonDown,
            changeCount: pasteboard.changeCount,
            idleChangeCount: idleChangeCount,
            hasAcceptedType: pasteboard.availableType(from: accepted) != nil
        )
    }

    /// The decision on its own, so the truth table can be tested directly.
    /// Getting this wrong opened the notch on every click, which is the kind of
    /// thing that should fail a check rather than a screen recording.
    static func dragInFlight(
        buttonDown: Bool,
        changeCount: Int,
        idleChangeCount: Int,
        hasAcceptedType: Bool
    ) -> Bool {
        guard buttonDown else { return false }
        // Leftovers from a finished drag are not a drag.
        guard changeCount != idleChangeCount else { return false }
        return hasAcceptedType
    }
}

/// Hosting view that only accepts mouse and drag events inside the island.
///
/// Everything outside `interactiveRect` hit-tests to `nil`, so clicks fall
/// through to the menu bar and whatever app is underneath. The rect is kept in
/// window coordinates (bottom-left origin) to avoid flipped-coordinate guesswork.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: CGRect = .zero

    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    /// Where the drag is, in this view's own (flipped, SwiftUI) coordinates,
    /// so a drop target inside the panel — the AirDrop zone — can light up.
    var onDragMoved: ((CGPoint) -> Void)?
    /// The drop, and where it landed in the same coordinates.
    var onDrop: ((NSPasteboard, CGPoint) -> Bool)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(NotchDragTypes.accepted)
    }

    /// Never answer with an operation the drag source did not offer — doing so
    /// gets the whole drop refused, which shows up as the ⊘ cursor and nothing
    /// else. Finder normally offers copy, but that is not guaranteed.
    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        let allowed = sender.draggingSourceOperationMask
        if allowed.contains(.copy) { return .copy }
        if allowed.contains(.generic) { return .generic }
        if allowed.contains(.link) { return .link }
        if allowed.contains(.move) { return .move }
        return allowed.isEmpty ? .copy : allowed
    }

    /// Let a drag or click land without first activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = operation(for: sender)
        Trace.log("drag", "entered mask=\(sender.draggingSourceOperationMask.rawValue) "
            + "types=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? []) -> op=\(op.rawValue)")
        onDragEntered?()
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragMoved?(convert(sender.draggingLocation, from: nil))
        return operation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard, convert(sender.draggingLocation, from: nil)) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    /// The panel deliberately overlaps the menu bar, and AppKit answers that by
    /// insetting the hosting view's safe area — which pushes the island down,
    /// leaves a strip of dead space above it, and makes the top of the pill
    /// unclickable even though it looks solid. We want the raw window rect.
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    /// While the island is closed there is nothing in it to click, so the panel
    /// hit-tests through to whatever is underneath — menu bar included. Opening
    /// is the pointer's job, never a click's.
    var isClosed: Bool = true

    private var hitTestCount = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Logged unconditionally (throttled) rather than only while a drag is
        // detected: gating the trace on our own drag detection meant that when
        // detection was wrong, the log went silent and looked like AppKit was
        // never asking at all.
        hitTestCount += 1
        if Trace.isEnabled, hitTestCount % 40 == 1 || NotchDragTypes.isDragInFlight {
            Trace.log("hit", "#\(hitTestCount) at \(point) closed=\(isClosed) "
                + "drag=\(NotchDragTypes.isDragInFlight) interactive=\(interactiveRect)")
        }

        // `point` arrives in the superview's coordinates; for a window's content
        // view that is the window's own coordinate space.
        //
        // `interactiveRect` is the whole panel while open, and just the black
        // pill while closed — so everything around a closed notch still falls
        // through to the menu bar. It deliberately does *not* consult
        // `isDragInFlight`: gating the drop target on our own guess about
        // whether a drag is happening means that whenever the guess is wrong
        // there is no drop target at all, and files land nowhere with nothing
        // logged. The pill has no click action, so capturing clicks on it costs
        // nothing.
        guard interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
