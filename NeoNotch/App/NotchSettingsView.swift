import SwiftUI

/// Settings, laid out for the notch itself rather than for a preferences window.
///
/// This is the only settings UI in the app. It lives in a tab because the panel
/// is where the app already is — an accessory app has no Dock icon and no
/// windows, so a separate preferences window is a place you have to go looking
/// for, and on top of that the standard way of opening one does not reliably
/// work for a `.accessory` app (see `AppDelegate.openSettings`).
struct NotchSettingsView: View {
    @ObservedObject var preferences: Preferences
    /// Apple Clock's connection, shown when the settings live in the notch.
    var clock: ClockBridge?
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        PanelCard {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Size and position first: they are the things you actually
                    // come in here to adjust.
                    section("Notch size and position") {
                        slider("Width", value: $preferences.virtualNotchWidth,
                               range: 120...420, step: 2,
                               format: "\(Int(preferences.virtualNotchWidth)) pt")
                        slider("Height", value: $preferences.virtualNotchHeight,
                               range: 18...44, step: 1,
                               format: "\(Int(preferences.virtualNotchHeight)) pt")
                        slider("Move left / right", value: $preferences.horizontalOffset,
                               range: -60...60, step: 1,
                               format: offsetLabel)
                        toggle("Always use a virtual notch", isOn: $preferences.forceVirtualNotch)
                    }

                    section("Home widgets") {
                        HomeWidgetPicker(preferences: preferences)
                        caption("Click a widget to show or hide it; the arrows change its place. Home is as wide as the widgets you keep.")
                    }

                    section("While a timer or music runs") {
                        slider("Width", value: $preferences.busyWidth,
                               range: 160...560, step: 2,
                               format: "\(Int(preferences.busyWidth)) pt")
                        caption("Grows sideways only, so it never reaches into the window you are working in. Wider covers more of the frontmost app's menus.")
                    }

                    section("Focus") {
                        slider("Focus", value: $preferences.focusMinutes,
                               range: 5...90, step: 5,
                               format: "\(Int(preferences.focusMinutes)) min")
                        slider("Short break", value: $preferences.shortBreakMinutes,
                               range: 1...30, step: 1,
                               format: "\(Int(preferences.shortBreakMinutes)) min")
                        slider("Long break", value: $preferences.longBreakMinutes,
                               range: 5...60, step: 5,
                               format: "\(Int(preferences.longBreakMinutes)) min")
                        slider("Sessions per cycle",
                               value: Binding(
                                   get: { Double(preferences.focusSprints) },
                                   set: { preferences.focusSprints = Int($0) }
                               ),
                               range: 2...8, step: 1,
                               format: "\(preferences.focusSprints)")
                        toggle("Start the next phase automatically", isOn: $preferences.focusAutoStart)
                        toggle("Play a sound when a phase ends", isOn: $preferences.focusSound)
                    }

                    if let clock {
                        section("Apple Clock") {
                            ClockConnectionView(clock: clock)
                        }
                    }

                    section("General") {
                        toggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                LoginItem.setEnabled(enabled)
                                // Re-read: macOS can park it in "requires
                                // approval" until allowed in System Settings.
                                launchAtLogin = LoginItem.isEnabled
                            }
                        toggle("Open on hover", isOn: $preferences.openOnHover)
                        slider("Hover delay", value: $preferences.hoverOpenDelay,
                               range: 0...0.5, step: 0.01,
                               format: preferences.hoverOpenDelay < 0.005
                                   ? "instant"
                                   : String(format: "%.02fs", preferences.hoverOpenDelay))
                        HStack(spacing: 10) {
                            Text("Open with the keyboard")
                                .font(.system(size: 11))
                                .frame(width: 132, alignment: .leading)
                            Picker("Open with the keyboard", selection: $preferences.toggleShortcut) {
                                ForEach(NotchShortcut.allCases) { shortcut in
                                    Text(shortcut.title).tag(shortcut)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(maxWidth: 260)
                        }
                    }

                    section("Clipboard") {
                        toggle("Track clipboard history", isOn: $preferences.clipboardEnabled)
                        toggle("Skip passwords and concealed items",
                               isOn: $preferences.ignoreConcealedClipboardItems)
                        toggle("Keep history across restarts (text and files)",
                               isOn: $preferences.keepClipboardHistory)
                        slider("History limit",
                               value: Binding(
                                   get: { Double(preferences.clipboardHistoryLimit) },
                                   set: { preferences.clipboardHistoryLimit = Int($0) }
                               ),
                               range: 10...300, step: 10,
                               format: "\(preferences.clipboardHistoryLimit)")
                    }

                    section("Battery and camera") {
                        toggle("Show the battery in the panel", isOn: $preferences.showBattery)
                        toggle("Show charging, and warn at 20% and 10%", isOn: $preferences.batteryAlerts)
                        toggle("Mirror the camera preview", isOn: $preferences.mirrorFlip)
                    }

                    section("Apple Intelligence") {
                        HStack(spacing: 6) {
                            Image(systemName: aiStatus.symbol)
                                .foregroundStyle(aiStatus.tint)
                            Text(aiStatus.text)
                                .font(.system(size: 11))
                                .foregroundStyle(NotchTheme.secondary)
                        }
                        caption("Rephrase and summarise in the clipboard, rephrase in notes, and the calendar's daily brief. Everything runs on this Mac.")
                    }

                    resetRow
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Reads "0 pt" as centred, and says which way it has been pushed.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.38))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var aiStatus: (symbol: String, tint: Color, text: String) {
        switch AIAssistant.availability {
        case .available:
            ("checkmark.circle.fill", .green, "Available — runs on this Mac")
        case .unavailable(let reason):
            ("exclamationmark.circle.fill", .orange, reason)
        }
    }

    private var offsetLabel: String {
        let offset = Int(preferences.horizontalOffset)
        if offset == 0 { return "centred" }
        return "\(offset > 0 ? "→" : "←") \(abs(offset)) pt"
    }

    private var resetRow: some View {
        HStack {
            Button {
                withAnimation(.notchSpring) { preferences.resetToDefaults() }
            } label: {
                Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(ShelfActionStyle())
            .disabled(preferences.isAtDefaults)
            .opacity(preferences.isAtDefaults ? 0.4 : 1)

            Text(preferences.isAtDefaults ? "Everything is at its default" : "")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    // MARK: Rows

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
            content()
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.system(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(.accentColor)
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 132, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .controlSize(.mini)
            Text(format)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func slider(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        slider(
            title,
            value: Binding(get: { Double(value.wrappedValue) },
                           set: { value.wrappedValue = CGFloat($0) }),
            range: range,
            step: step,
            format: format
        )
    }
}

/// Which of the Clock shortcuts exist, and how to make the rest.
private struct ClockConnectionView: View {
    @ObservedObject var clock: ClockBridge

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 8, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Timers and the stopwatch you start in Clock show up in the notch by themselves.")
                .font(.system(size: 11))
            Text("To start and stop them from the notch too, make a shortcut for each action you want: in Shortcuts, create a shortcut, add Clock's action of that name, and name the shortcut exactly as below. In Start Timer, set the duration to Shortcut Input, in minutes.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(ClockBridge.Command.allCases) { command in
                    let found = clock.has(command)
                    HStack(spacing: 6) {
                        Image(systemName: found ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(found ? Color.green : NotchTheme.tertiary)
                        Text(command.shortcutName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(found ? NotchTheme.primary : NotchTheme.secondary)
                            .textSelection(.enabled)
                    }
                    .help(found ? "Found" : "Make it in Shortcuts with Clock's “\(command.clockAction)” action")
                }
            }

            HStack(spacing: 8) {
                Button("Open Shortcuts") { clock.openShortcuts() }
                    .buttonStyle(ShelfActionStyle())
                Button("Check again") { clock.refreshShortcuts(force: true) }
                    .buttonStyle(ShelfActionStyle())
            }
        }
    }
}

/// The Home widgets as chips: the ones shown come first, in their order, with
/// arrows to move them; hidden ones follow, dimmed. Click a chip to show or
/// hide it.
private struct HomeWidgetPicker: View {
    @ObservedObject var preferences: Preferences

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 8, alignment: .leading)]

    var body: some View {
        let shown = preferences.homeModules
        let hidden = HomeModule.allCases.filter { !shown.contains($0) }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.element) { index, module in
                chip(module, isShown: true, isFirst: index == 0, isLast: index == shown.count - 1)
            }
            ForEach(hidden) { module in
                chip(module, isShown: false, isFirst: false, isLast: false)
            }
        }
        .animation(.notchSpring, value: preferences.homeModules)
    }

    private func chip(_ module: HomeModule, isShown: Bool, isFirst: Bool, isLast: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                preferences.setModule(module, enabled: !isShown)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShown ? module.symbol : "plus")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 14)
                    Text(module.title)
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isShown ? "Hide \(module.title)" : "Show \(module.title)")

            if isShown {
                arrow("chevron.left", disabled: isFirst) { preferences.moveModule(module, by: -1) }
                arrow("chevron.right", disabled: isLast) { preferences.moveModule(module, by: 1) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isShown ? NotchTheme.fillSelected : NotchTheme.fill)
        )
        .foregroundStyle(isShown ? NotchTheme.primary : NotchTheme.tertiary)
    }

    private func arrow(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.85))
        .disabled(disabled)
        .opacity(disabled ? 0.25 : 0.8)
    }
}
