import AppKit
import SwiftUI

/// One set of values for every tab, so the panel reads as a single object.
///
/// Content sits straight on the black — no cards — and sections are split by
/// hairlines. Hierarchy comes from white at a few fixed opacities rather than
/// from boxes, which is what keeps a panel this small from looking cluttered.
enum NotchTheme {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.68)
    static let tertiary = Color.white.opacity(0.45)
    static let quaternary = Color.white.opacity(0.28)

    static let fill = Color.white.opacity(0.07)
    static let fillHover = Color.white.opacity(0.12)
    static let fillSelected = Color.white.opacity(0.16)

    static let separator = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.08)

    /// Section captions ("STOPWATCH", "GENERAL").
    static let caption = Font.system(size: 9.5, weight: .semibold)
}

extension View {
    /// A card floating over the panel — a result, a small form. Lifted off
    /// the black by a lighter fill, a hairline edge and a soft shadow.
    func notchCard(cornerRadius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 16, y: 6)
        )
    }
}

/// Hairline between sections of a tab.
struct NotchDivider: View {
    var axis: Axis = .vertical

    var body: some View {
        Rectangle()
            .fill(NotchTheme.separator)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

/// Shrinks a touch while pressed, so a click is felt as well as seen.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Capsule button used across the panel. `prominent` is the one action a view
/// most wants you to take: white, with black text.
struct NotchPillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, destructive: destructive, compact: compact)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let destructive: Bool
        let compact: Bool

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, compact ? 9 : 12)
                .padding(.vertical, compact ? 3.5 : 5)
                .background(Capsule().fill(background))
                .foregroundStyle(foreground)
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering && isEnabled }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
        }

        private var background: Color {
            if prominent {
                return .white.opacity(configuration.isPressed ? 0.78 : (isHovering ? 1 : 0.92))
            }
            return .white.opacity(configuration.isPressed ? 0.2 : (isHovering ? 0.15 : 0.1))
        }

        private var foreground: Color {
            if prominent { return .black }
            return destructive ? Color(red: 1, green: 0.45, blue: 0.42) : .white.opacity(0.88)
        }
    }
}

/// Round icon button that lights up under the pointer.
struct NotchIconButton: View {
    let systemName: String
    var help: String
    var size: CGFloat = 11
    var diameter: CGFloat = 24
    /// Held in `activeTint` instead of the usual grey, e.g. a pinned pin.
    var isActive = false
    var activeTint: Color = .white
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isActive ? activeTint : (isHovering ? NotchTheme.primary : NotchTheme.secondary))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(isHovering ? NotchTheme.fillHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
    }
}

/// Level bars that read as "audio".
///
/// Each bar runs its own pair of sine waves, so the motion never visibly loops
/// the way a single repeating animation does. When playback pauses they settle
/// flat instead of vanishing, which is what tells you it paused.
struct AudioBars: View {
    var isAnimating = true
    var tint: Color = .white
    var barCount = 4
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var minHeight: CGFloat = 3
    var maxHeight: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: height(for: index, at: time))
                }
            }
            .frame(height: maxHeight)
        }
        .animation(.easeOut(duration: 0.35), value: isAnimating)
    }

    private func height(for index: Int, at time: Double) -> CGFloat {
        guard isAnimating else { return minHeight }
        let speeds: [Double] = [5.3, 7.1, 4.6, 6.2, 5.8]
        let offsets: [Double] = [0, 1.9, 3.7, 0.8, 2.6]
        let slot = index % speeds.count
        let primary = sin(time * speeds[slot] + offsets[slot])
        let secondary = sin(time * speeds[(slot + 2) % speeds.count] * 0.47 + offsets[(slot + 3) % speeds.count])
        let level = (primary * 0.62 + secondary * 0.38 + 1) / 2
        return minHeight + (maxHeight - minHeight) * CGFloat(level)
    }
}

/// One line of text that scrolls when it does not fit — pausing at the start
/// of each pass — and sits still like ordinary text when it does.
///
/// Driven by a timeline rather than a repeating animation, so a new title
/// restarts it cleanly instead of inheriting the old one's position.
struct MarqueeText: View {
    let text: String
    let font: NSFont
    var color: Color = NotchTheme.primary
    /// Points per second.
    var speed: Double = 30
    var gap: CGFloat = 36
    var pause: Double = 2.4

    @State private var startedAt = Date()

    private var textWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        // The hidden copy gives the view its natural height and lets it take
        // whatever width it is offered, like a plain truncating label would.
        label
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let overflows = textWidth > geometry.size.width + 0.5
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !overflows)) { context in
                        let offset = overflows ? offset(at: context.date) : 0
                        HStack(spacing: gap) {
                            label
                            if overflows { label }
                        }
                        .fixedSize()
                        .offset(x: offset)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                        .clipped()
                        // Fade the trailing edge whenever text runs past it,
                        // the leading edge only while text is sliding under it.
                        .mask(edgeFade(leading: offset < 0, trailing: overflows))
                    }
                }
            }
            .onChange(of: text) { startedAt = Date() }
    }

    private var label: some View {
        Text(text)
            .font(Font(font))
            .foregroundStyle(color)
    }

    private func edgeFade(leading: Bool, trailing: Bool) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: leading ? .clear : .black, location: 0),
                .init(color: .black, location: leading ? 0.05 : 0),
                .init(color: .black, location: trailing ? 0.88 : 1),
                .init(color: trailing ? .clear : .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = Double(textWidth + gap)
        let cycle = pause + distance / speed
        let elapsed = max(0, date.timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: cycle)
        guard elapsed > pause else { return 0 }
        return -CGFloat((elapsed - pause) * speed)
    }
}
