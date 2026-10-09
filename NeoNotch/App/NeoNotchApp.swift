import AppKit
import SwiftUI

@main
struct NeoNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The notch panel is driven by the delegate, not by a Scene, so the app
        // has no windows of its own. `Settings` satisfies SwiftUI's requirement
        // for at least one scene and backs ⌘, — but the settings you actually
        // reach live in the notch's own Settings tab, because opening this
        // window is unreliable for an accessory app (see `openSettings`).
        Settings {
            NotchSettingsView(preferences: .shared)
                .frame(width: 460, height: 360)
                .background(Color.black)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, never steals focus.
        NSApp.setActivationPolicy(.accessory)

        if let paths = DropSelfTest.requestedPaths() {
            exit(DropSelfTest.run(paths: paths))
        }

        if MusicSelfTest.isRequested {
            exit(MusicSelfTest.run())
        }

        if WidgetSelfTest.isRequested {
            exit(WidgetSelfTest.run())
        }

        if let directory = Snapshotter.requestedDirectory() {
            Snapshotter.run(into: directory)
            NSApp.terminate(nil)
            return
        }

        TimerNotifier.requestAuthorization()

        let controller = NotchWindowController()
        // No longer opens the panel: a finished timer rings in the closed notch
        // and clears itself, rather than holding the panel over your work.
        controller.viewModel.timers.onFire = { [weak controller] in
            guard let controller else { return }
            // The island is invisible on the lock screen, so a notification is
            // the only way a timer that fires while locked actually reaches you.
            TimerNotifier.timerFinished(
                label: controller.viewModel.timers.active?.label ?? "Time's up"
            )
        }
        controller.start()
        self.controller = controller

        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    // MARK: Menu bar extra

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "NeoNotch"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Notch",
            action: #selector(openNotch),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit NeoNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() {
        guard let controller else { return }
        // Pinned: the pointer is up at the menu bar item, not on the island,
        // and hover tracking would otherwise close the panel straight away.
        controller.viewModel.isPinned = true
        withAnimation(.notchSpring) { controller.viewModel.open() }
    }

    /// Opens the notch on its Settings tab.
    ///
    /// This used to call `showSettingsWindow:` through the responder chain, and
    /// it did nothing at all. That action is delivered by the responder chain,
    /// and an accessory app with no Dock icon and no open windows has nothing in
    /// it to receive the action — so `sendAction` returned false and the click
    /// silently went nowhere. Driving our own panel needs no responder chain.
    @objc private func openSettings() {
        guard let controller else { return }
        controller.viewModel.isPinned = true
        withAnimation(.notchSnap) { controller.viewModel.open(tab: .settings) }
    }
}
