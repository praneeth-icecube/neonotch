import SwiftUI

/// Home's timer, drawn like Apple's Clock: the timer that is running —
/// Clock's or NeoNotch's — with its pause and cancel, or, with nothing
/// running, your Recents, each a click away from starting.
struct TimerModuleView: View {
    @ObservedObject var timers: TimerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClockStyle.secondary)
                Spacer(minLength: 0)
                if timers.active?.isClock == true {
                    Text("Clock")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ClockStyle.secondary)
                        .textCase(.uppercase)
                }
            }

            if let active = timers.active {
                running(active)
                    .transition(.opacity)
            } else {
                recents
                    .transition(.opacity)
            }
        }
        .animation(.notchSpring, value: timers.active == nil)
    }

    // MARK: Running

    private func running(_ active: NotchCountdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(NotchCountdown.format(active.remaining(at: context.date)))
                        .font(ClockStyle.digits(active.duration >= 3600 ? 28 : 32))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(timers.didFire ? "Done" : active.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ClockStyle.secondary)
            }

            // How much is gone, in Clock's orange.
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ClockStyle.ringTrack)
                        Capsule()
                            .fill(ClockStyle.orange)
                            .frame(width: proxy.size.width * max(0, 1 - active.progress(at: context.date)))
                    }
                }
            }
            .frame(height: 3)

            HStack(spacing: 10) {
                pauseResume(active)
                cancel
            }
        }
    }

    /// Orange ring and pause while it runs; green disc and play while paused.
    private func pauseResume(_ active: NotchCountdown) -> some View {
        let isRunning = active.isRunning
        let command: ClockBridge.Command = isRunning ? .pauseTimer : .resumeTimer
        let enabled = !timers.didFire && timers.canControl(command)
        return Button {
            isRunning ? timers.pause() : timers.resume()
        } label: {
            ZStack {
                if isRunning {
                    Circle().strokeBorder(ClockStyle.orange, lineWidth: 2)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ClockStyle.orange)
                } else {
                    Circle().fill(ClockStyle.greenDisc)
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ClockStyle.green)
                        .offset(x: 1)
                }
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled || timers.didFire ? 1 : 0.35)
        .help(enabled ? (isRunning ? "Pause" : "Resume")
                      : "Make the “\(command.shortcutName)” shortcut to do this from the notch")
    }

    private var cancel: some View {
        let enabled = timers.didFire || timers.canControl(.cancelTimer)
        return Button {
            withAnimation(.notchSpring) {
                timers.didFire ? timers.acknowledgeFire() : timers.cancel()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(ClockStyle.grayButton))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(enabled ? "Cancel" : "Make the “NeoNotch Cancel Timer” shortcut to do this from the notch")
    }

    // MARK: Recents

    private var recents: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(timers.recents.enumerated()), id: \.element.id) { index, recent in
                    if index > 0 {
                        ClockStyle.separator.frame(height: 1)
                    }
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(NotchCountdown.format(recent.duration))
                                .font(ClockStyle.digits(22))
                                .foregroundStyle(ClockStyle.recentDigits)
                            Text(NotchCountdown.words(for: recent.duration))
                                .font(.system(size: 10.5))
                                .foregroundStyle(ClockStyle.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.notchSpring) { timers.start(seconds: recent.duration) }
                        } label: {
                            ZStack {
                                Circle().fill(ClockStyle.greenDisc)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(ClockStyle.green)
                                    .offset(x: 1)
                            }
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                        }
                        .buttonStyle(PressScaleStyle())
                        .help("Start \(NotchCountdown.words(for: recent.duration))")
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}
