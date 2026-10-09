import SwiftUI

/// What the island shows while it is closed.
///
/// Idle it is deliberately empty — a plain black strip that reads as part of the
/// menu bar. When a timer, stopwatch or playback is live it grows sideways and
/// shows a compact readout.
struct CollapsedView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        Group {
            if let indicator = viewModel.collapsedIndicator {
                busyContent(indicator)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = .notchSpring }
    }

    /// The headline sits dead centre of the pill, with the icon mirrored by an
    /// equal gutter on the right.
    ///
    /// Laying icon and text out as one centred group is the obvious thing and it
    /// is wrong: it pushes the readout ~11 pt right of the island's centre line.
    /// The readout is what the eye lines up against the camera, so the black
    /// then reads as extending too far left even though the pill is centred to
    /// the pixel.
    private func busyContent(_ indicator: NotchViewModel.CollapsedIndicator) -> some View {
        ZStack {
            Text(indicator.text)
                .font(Font(NotchViewModel.busyFont))
                .lineLimit(1)
                .foregroundStyle(.white)
                // Truncate before the gutters rather than running under them.
                .padding(.horizontal, Self.gutter + 8)

            HStack(spacing: 8) {
                leading(indicator)
                    .frame(width: Self.gutter, alignment: .leading)

                Spacer(minLength: 0)

                trailing(indicator)
                    .frame(width: Self.gutter, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func leading(_ indicator: NotchViewModel.CollapsedIndicator) -> some View {
        if let artwork = indicator.artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.gutter, height: Self.gutter)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .id(ObjectIdentifier(artwork))
                .transition(.opacity)
        } else {
            Image(systemName: indicator.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(indicator.tint)
        }
    }

    @ViewBuilder
    private func trailing(_ indicator: NotchViewModel.CollapsedIndicator) -> some View {
        if indicator.showsAudioBars {
            AudioBars(isAnimating: indicator.isAnimating, tint: indicator.tint)
        } else if let progress = indicator.progress {
            ProgressRing(progress: progress, tint: indicator.tint)
        } else {
            Color.clear
        }
    }

    /// Sized to sit comfortably inside the menu bar strip, which is all the
    /// vertical room the closed island ever gets.
    private static let gutter: CGFloat = NotchViewModel.collapsedGutter
}

/// How much of the running timer is gone, as a ring.
struct ProgressRing: View {
    var progress: Double
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
    }
}
