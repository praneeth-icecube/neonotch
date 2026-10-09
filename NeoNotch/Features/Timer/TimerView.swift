import SwiftUI

/// Apple Clock's look, colour for colour: SF Pro at light and thin weights for
/// time, system orange for a running timer, system green to start one, system
/// red to stop, and grey capsules and cards — the dark-appearance values.
/// Shared by the Timer tab and Home's timer.
enum ClockStyle {
    static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let green = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    /// The dark green disc behind a play button.
    static let greenDisc = Color(red: 34 / 255, green: 66 / 255, blue: 44 / 255)
    /// The running timer's card.
    static let card = Color(red: 60 / 255, green: 60 / 255, blue: 62 / 255)
    /// Cancel, Lap and Reset.
    static let grayButton = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
    static let secondary = Color(red: 152 / 255, green: 152 / 255, blue: 157 / 255)
    /// Recents are drawn a step quieter than the timer that is running.
    static let recentDigits = Color(white: 0.68)
    static let separator = Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
    static let ringTrack = Color(white: 0.19)

    static func digits(_ size: CGFloat, _ weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// The Timer tab, drawn the way Apple's Clock draws its Timers: the running
/// timer's card and Recents down the left, the countdown ring — or, with
/// nothing running, the picker — in the middle, and the stopwatch on the right.
struct TimerView: View {
    @ObservedObject var viewModel: NotchViewModel

    private var timers: TimerModel { viewModel.timers }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 292)
            separator
            Group {
                if let active = timers.active {
                    ring(active)
                } else {
                    picker
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            separator
            stopwatch
                .frame(width: 244)
        }
        // Shortcuts made since the last look are picked up here.
        .onAppear { timers.clock.refreshShortcuts() }
    }

    private var separator: some View {
        ClockStyle.separator
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    // MARK: Left — the running timer and Recents

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let active = timers.active {
                runningCard(active)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("Recents")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClockStyle.secondary)
                .padding(.leading, 14)
                .padding(.bottom, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(timers.recents) { recent in
                        ClockStyle.separator
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                        recentRow(recent)
                    }
                }
            }
        }
        .padding(.trailing, 10)
        .animation(.notchSpring, value: timers.active == nil)
    }

    private func runningCard(_ active: NotchCountdown) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(NotchCountdown.format(active.remaining(at: context.date)))
                        .font(ClockStyle.digits(36))
                        .foregroundStyle(.white)
                }
                Text(active.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            pauseResumeButton(active)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ClockStyle.card)
        )
    }

    /// An orange ring with a pause while it runs; a green disc with a play
    /// while it is paused.
    private func pauseResumeButton(_ active: NotchCountdown) -> some View {
        let running = active.isRunning
        let command: ClockBridge.Command = running ? .pauseTimer : .resumeTimer
        let enabled = !timers.didFire && timers.canControl(command)
        return Button {
            running ? timers.pause() : timers.resume()
        } label: {
            ZStack {
                if running {
                    Circle()
                        .strokeBorder(ClockStyle.orange, lineWidth: 2)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ClockStyle.orange)
                } else {
                    playDisc
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled || timers.didFire ? 1 : 0.35)
        .help(controlHelp(command, fallback: running ? "Pause" : "Resume"))
    }

    private var playDisc: some View {
        ZStack {
            Circle()
                .fill(ClockStyle.greenDisc)
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ClockStyle.green)
                .offset(x: 1.5)
        }
    }

    private func recentRow(_ recent: TimerRecent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(NotchCountdown.format(recent.duration))
                    .font(ClockStyle.digits(32))
                    .foregroundStyle(ClockStyle.recentDigits)
                Text(NotchCountdown.words(for: recent.duration))
                    .font(.system(size: 11.5))
                    .foregroundStyle(ClockStyle.secondary)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.notchSpring) { timers.start(seconds: recent.duration) }
            } label: {
                playDisc
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .help("Start \(NotchCountdown.words(for: recent.duration))")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: Middle — the countdown ring, or the picker

    private func ring(_ active: NotchCountdown) -> some View {
        VStack(spacing: 12) {
            // Sampled per frame, so the ring sweeps rather than steps.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                ZStack {
                    Circle()
                        .stroke(ClockStyle.ringTrack, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - active.progress(at: context.date)))
                        .stroke(ClockStyle.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        if let end = active.endDate {
                            Label(end.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(ClockStyle.secondary)
                        }
                        Text(NotchCountdown.format(active.remaining(at: context.date)))
                            .font(ClockStyle.digits(34, .thin))
                            .foregroundStyle(.white)
                        Text(active.customTitle ?? (active.isClock ? "Clock" : "Timer"))
                            .font(.system(size: 11))
                            .foregroundStyle(ClockStyle.secondary)
                    }
                }
            }
            .frame(width: 142, height: 142)

            HStack(spacing: 12) {
                clockButton("Cancel", fill: ClockStyle.grayButton,
                            enabled: timers.didFire || timers.canControl(.cancelTimer)) {
                    withAnimation(.notchSpring) {
                        timers.didFire ? timers.acknowledgeFire() : timers.cancel()
                    }
                }
                .help(controlHelp(.cancelTimer, fallback: "Cancel"))

                if active.isRunning || timers.didFire {
                    clockButton("Pause", fill: ClockStyle.orange,
                                enabled: !timers.didFire && timers.canControl(.pauseTimer)) {
                        timers.pause()
                    }
                    .help(controlHelp(.pauseTimer, fallback: "Pause"))
                } else {
                    clockButton("Resume", fill: ClockStyle.green, enabled: timers.canControl(.resumeTimer)) {
                        timers.resume()
                    }
                    .help(controlHelp(.resumeTimer, fallback: "Resume"))
                }
            }

            // A Clock timer whose controls have no shortcut yet.
            if active.isClock, active.clockID != TimerModel.pendingClockID, !timers.canControl(.cancelTimer) {
                Button("Open Clock") { timers.clock.openClock() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(ClockStyle.orange)
            }
        }
    }

    private var picker: some View {
        let total = Int(timers.draftDuration)
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                pickerColumn(.hours, value: total / 3600, unit: "hr")
                colon
                pickerColumn(.minutes, value: (total % 3600) / 60, unit: "min")
                colon
                pickerColumn(.seconds, value: total % 60, unit: "sec")
            }

            HStack(spacing: 12) {
                clockButton("Cancel", fill: ClockStyle.grayButton, enabled: false) {}
                clockButton("Start", fill: ClockStyle.green, enabled: total > 0) {
                    withAnimation(.notchSpring) { timers.start(seconds: timers.draftDuration) }
                }
            }
        }
    }

    private var colon: some View {
        Text(":")
            .font(ClockStyle.digits(40, .thin))
            .foregroundStyle(.white)
            .padding(.top, 18)
    }

    private func pickerColumn(_ component: TimerModel.DraftComponent, value: Int, unit: String) -> some View {
        VStack(spacing: 0) {
            stepButton("chevron.up") { timers.stepDraft(component, by: 1) }
            Text(String(format: "%02d", value))
                .font(ClockStyle.digits(40, .thin))
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(value)))
                .animation(.snappy(duration: 0.18), value: value)
            stepButton("chevron.down") { timers.stepDraft(component, by: -1) }
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(ClockStyle.secondary)
        }
        .frame(width: 64)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ClockStyle.secondary)
                .frame(width: 44, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.85))
    }

    // MARK: Right — the stopwatch

    private var stopwatch: some View {
        VStack(spacing: 10) {
            Text(timers.clockStopwatch == nil ? "Stopwatch" : "Stopwatch · Clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClockStyle.secondary)

            // Hundredths need a per-frame sample; driving this from the
            // model's tick is what once made it step 0.00, 0.25, 0.50, 0.75.
            TimelineView(.animation) { context in
                Text(NotchCountdown.formatPrecise(timers.stopwatchElapsed(at: context.date)))
                    .font(ClockStyle.digits(32, .thin))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                if timers.isStopwatchRunning {
                    clockButton("Lap", fill: ClockStyle.grayButton, width: 88, enabled: timers.canLap) {
                        timers.lapStopwatch()
                    }
                    clockButton("Stop", fill: ClockStyle.red, width: 88, enabled: timers.canToggleStopwatch) {
                        timers.toggleStopwatch()
                    }
                } else {
                    clockButton("Reset", fill: ClockStyle.grayButton, width: 88, enabled: timers.canResetStopwatch) {
                        timers.resetStopwatch()
                    }
                    clockButton("Start", fill: ClockStyle.green, width: 88, enabled: timers.canToggleStopwatch) {
                        timers.toggleStopwatch()
                    }
                }
            }

            if timers.clockStopwatch != nil, !timers.canToggleStopwatch {
                Button("Open Clock") { timers.clock.openClock() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(ClockStyle.orange)
            }

            laps
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The last few laps, newest first, the way Clock lists them.
    private var laps: some View {
        let recent = Array(timers.laps.enumerated().reversed().prefix(3))
        return VStack(spacing: 0) {
            ForEach(recent, id: \.offset) { index, lap in
                ClockStyle.separator.frame(height: 1)
                HStack {
                    Text("Lap \(index + 1)")
                    Spacer()
                    Text(NotchCountdown.formatPrecise(lap))
                        .monospacedDigit()
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.vertical, 4)
            }
        }
        .frame(width: 186)
    }

    // MARK: Controls

    /// Clock's capsule buttons: white label on a filled capsule.
    private func clockButton(
        _ title: String,
        fill: Color,
        width: CGFloat = 104,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: width, height: 28)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    /// Why a Clock timer's control is greyed out, when it is.
    private func controlHelp(_ command: ClockBridge.Command, fallback: String) -> String {
        timers.canControl(command) ? fallback : "Make the “\(command.shortcutName)” shortcut to do this from the notch"
    }
}
