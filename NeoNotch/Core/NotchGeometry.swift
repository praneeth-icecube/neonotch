import AppKit

/// Everything we need to know about where the notch lives on a given screen.
///
/// Macs with a camera housing report it through `safeAreaInsets` plus the two
/// `auxiliaryTop*Area` rects. Machines without one (including this MacBook Neo)
/// report nothing, so we synthesise a "virtual notch" that sits in the menu bar
/// at top centre and behaves identically from the UI's point of view.
struct NotchMetrics: Equatable {
    /// True when the display has a real camera housing we are hugging.
    var hasPhysicalNotch: Bool
    /// Size of the island in its collapsed state, in points.
    var collapsedSize: CGSize
    /// Full screen frame, in global (bottom-left origin) coordinates.
    var screenFrame: CGRect
    /// Height of the menu bar on this screen.
    var menuBarHeight: CGFloat

    static let zero = NotchMetrics(
        hasPhysicalNotch: false,
        collapsedSize: .zero,
        screenFrame: .zero,
        menuBarHeight: 0
    )
}

enum NotchGeometry {
    /// The screen we should attach to: the one with a physical notch if any,
    /// otherwise the screen holding the menu bar.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { physicalNotchSize(on: $0) != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Size of the real camera housing, or nil when this display has none.
    static func physicalNotchSize(on screen: NSScreen) -> CGSize? {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        let width = screen.frame.width - left.width - right.width
        guard width > 1 else { return nil }
        return CGSize(width: width, height: topInset)
    }

    /// Height of the menu bar strip on this screen.
    ///
    /// `visibleFrame` is inset by the menu bar at the top and the Dock wherever
    /// it happens to be, so the top inset is the difference between the two maxYs.
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let inset = screen.frame.maxY - screen.visibleFrame.maxY
        // Guard against odd configurations (menu bar auto-hidden, mirrored displays).
        return inset > 1 ? inset : NSStatusBar.system.thickness
    }

    static func metrics(for screen: NSScreen, preferences: Preferences) -> NotchMetrics {
        let menuBar = menuBarHeight(on: screen)

        if !preferences.forceVirtualNotch, let physical = physicalNotchSize(on: screen) {
            return NotchMetrics(
                hasPhysicalNotch: true,
                collapsedSize: physical,
                screenFrame: screen.frame,
                menuBarHeight: menuBar
            )
        }

        // Virtual notch: as tall as the menu bar so it reads as part of the strip.
        let height = min(max(preferences.virtualNotchHeight, 18), menuBar)
        return NotchMetrics(
            hasPhysicalNotch: false,
            collapsedSize: CGSize(width: preferences.virtualNotchWidth, height: height),
            screenFrame: screen.frame,
            menuBarHeight: menuBar
        )
    }
}
