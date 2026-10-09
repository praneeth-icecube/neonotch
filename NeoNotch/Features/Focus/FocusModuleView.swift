import SwiftUI

/// The Pomodoro widget: the phase as a tinted pill, the time large and
/// monospaced, a thin progress line, and reset / play / skip.
struct FocusModuleView: View {
    @ObservedObject var focus: FocusModel

    var body: some View {
        let tint = focus.phase.tint
        VStack(spacing: 0) {
            phasePill(tint: tint)
            Spacer(minLength: 6)
            TimelineView(.animation(minimumInterval: 0.25, paused: !focus.isRunning)) { context in
                VStack(spacing: 8) {
                    Text(Self.format(focus.remaining(at: context.date)))
                        .font(.system(size: 34, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .tracking(-0.6)
                        .foregroundStyle(focus.isRunning ? tint : NotchTheme.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3))
                        Capsule()
                            .fill(tint)
                            .frame(width: 96 * focus.progress(at: context.date))
                    }
                    .frame(width: 96, height: 2)
                }
            }
            Spacer(minLength: 6)
            controls(tint: tint)
            if focus.streak > 0 {
                Text("\(focus.streak)-day streak · \(focus.completedToday) today")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(NotchTheme.tertiary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: focus.phase)
    }

    private func phasePill(tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: focus.phase.symbol)
                .font(.system(size: 10.5, weight: .semibold))
            Text(focus.phase.title)
                .font(.system(size: 11, weight: .medium))
            if focus.phase == .focus {
                Text("(\(focus.sprint)/\(focus.sprints))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.secondary)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.13)))
    }

    private func controls(tint: Color) -> some View {
        HStack(spacing: 14) {
            circleButton("arrow.counterclockwise", size: 26, glyph: 11, fill: NotchTheme.fill, help: "Reset") {
                withAnimation(.notchSpring) { focus.reset() }
            }
            circleButton(
                focus.isRunning ? "pause.fill" : "play.fill",
                size: 34,
                glyph: 14,
                fill: tint.opacity(0.22),
                help: focus.isRunning ? "Pause" : (focus.isActive ? "Resume" : "Start \(focus.phase.title.lowercased())")
            ) {
                focus.toggle()
            }
            circleButton("forward.end.fill", size: 26, glyph: 11, fill: NotchTheme.fill, help: "Skip to the next phase") {
                withAnimation(.notchSpring) { focus.skip() }
            }
        }
    }

    private func circleButton(
        _ symbol: String,
        size: CGFloat,
        glyph: CGFloat,
        fill: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .foregroundStyle(NotchTheme.primary)
        .help(help)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
