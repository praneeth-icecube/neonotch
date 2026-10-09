import AppKit
import SwiftUI

/// Now playing: the cover on the left, everything you can do with it on the
/// right, straight on the black like the rest of the panel.
struct MusicView: View {
    @ObservedObject var viewModel: NotchViewModel

    private var music: MusicModel { viewModel.music }

    var body: some View {
        ZStack {
            if let track = music.track, let source = music.source {
                NowPlayingPanel(music: music, track: track, source: source)
                    .transition(.opacity)
            } else {
                MusicIdleView(music: music)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: music.track == nil)
        // The panel is as wide as Home; a player stretched across all of it
        // would have a scrubber longer than the song.
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onAppear { music.panelDidAppear() }
    }
}

// MARK: - Playing

private struct NowPlayingPanel: View {
    @ObservedObject var music: MusicModel
    let track: NowPlayingTrack
    let source: MusicSource

    static let coverSize: CGFloat = 116
    static let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            CoverArt(
                image: music.artwork,
                source: source,
                isPlaying: music.isPlaying,
                size: Self.coverSize
            )
            .onTapGesture { music.openPlayer() }
            .help("Open \(source.displayName)")

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 10)
                PlaybackScrubber(
                    clock: music.clock,
                    duration: track.duration,
                    isPlaying: music.isPlaying,
                    onSeek: music.seek(to:)
                )
                Spacer(minLength: 6)
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: Self.coverSize + 6, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(
                    text: track.title.isEmpty ? source.displayName : track.title,
                    font: Self.titleFont
                )
                Text(track.subtitle(fallback: source.displayName))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchTheme.secondary)
                    .lineLimit(1)
            }
            AudioBars(isAnimating: music.isPlaying, tint: music.palette.accentColor)
                .padding(.top, 3)
                .help(music.isPlaying ? "Playing in \(source.displayName)" : "Paused")
        }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            TransportButton(symbol: "backward.fill", size: 15, help: "Previous", action: music.previousTrack)
            TransportButton(
                symbol: music.isPlaying ? "pause.fill" : "play.fill",
                size: 22,
                help: music.isPlaying ? "Pause" : "Play",
                action: music.playPause
            )
            TransportButton(symbol: "forward.fill", size: 15, help: "Next", action: music.nextTrack)

            Spacer(minLength: 10)

            if music.canControl {
                if let volume = music.volume {
                    VolumeControl(level: volume, onChange: music.setVolume)
                }
            } else {
                PermissionPill(music: music, source: source)
            }
        }
        // The glyphs, not their hover circles, line up with the text above.
        .padding(.leading, -9)
    }
}

/// The cover, lit from behind by a blurred copy of itself, with the player's
/// badge on its corner. It eases back a touch while paused, like a record
/// being lifted off the platter.
struct CoverArt: View {
    let image: NSImage?
    let source: MusicSource
    let isPlaying: Bool
    let size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            glow
            cover
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(NotchTheme.stroke, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            SourceBadge(source: source, size: min(28, size * 0.25))
                .offset(x: size * 0.06, y: size * 0.06)
        }
        .frame(width: size, height: size)
        .scaleEffect(isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isPlaying)
        .animation(.easeInOut(duration: 0.35), value: image.map(ObjectIdentifier.init))
    }

    /// The cover's own light spilling onto the black behind it. Only for a
    /// real cover: a glowing placeholder just reads as a grey smudge.
    @ViewBuilder
    private var glow: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(shape)
                .blur(radius: 20)
                .opacity(isPlaying ? 0.6 : 0.25)
                .scaleEffect(0.94)
                .offset(y: 8)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .id(ObjectIdentifier(image))
                .transition(.opacity)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .transition(.opacity)
        }
    }
}

/// The player's own icon, so you can tell at a glance where this is coming from.
struct SourceBadge: View {
    let source: MusicSource
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = source.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.gray))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

/// Thin bar you can drag or click anywhere to seek, with elapsed and remaining
/// time underneath. Reads the position off the clock for every frame it draws,
/// so it moves smoothly without the model publishing anything.
struct PlaybackScrubber: View {
    let clock: PlaybackClock
    let duration: Double
    let isPlaying: Bool
    var tint: Color = .white
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var isHovering = false

    private var canSeek: Bool { duration > 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying || dragFraction != nil)) { context in
            let live = clamped(clock.position(at: context.date))
            let position = dragFraction.map { $0 * duration } ?? live
            VStack(spacing: 5) {
                bar(fraction: canSeek ? position / duration : 0)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text(canSeek ? "-" + Self.format(max(0, duration - position)) : "Live")
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.tertiary)
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        let isActive = canSeek && (isHovering || dragFraction != nil)
        let thickness: CGFloat = isActive ? 7 : 5
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(tint)
                    .frame(width: max(thickness, geometry.size.width * min(max(fraction, 0), 1)))
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek, geometry.size.width > 0 else { return }
                        dragFraction = min(max(value.location.x / geometry.size.width, 0), 1)
                    }
                    .onEnded { value in
                        guard canSeek, geometry.size.width > 0 else { return }
                        let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                        onSeek(fraction * duration)
                        dragFraction = nil
                    }
            )
        }
        .frame(height: 12)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .animation(.easeOut(duration: 0.14), value: dragFraction != nil)
    }

    private func clamped(_ position: Double) -> Double {
        canSeek ? min(max(position, 0), duration) : max(position, 0)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: size + 19, height: size + 19)
                .background(Circle().fill(isHovering ? NotchTheme.fillHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.86))
        .foregroundStyle(NotchTheme.primary)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
    }
}

struct VolumeControl: View {
    let level: Double
    let onChange: (Double) -> Void

    @State private var dragLevel: Double?
    @State private var isHovering = false

    var body: some View {
        let shown = dragLevel ?? level
        HStack(spacing: 7) {
            Image(systemName: Self.symbol(for: shown))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.secondary)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { geometry in
                let thickness: CGFloat = isHovering || dragLevel != nil ? 6 : 4
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: max(thickness, geometry.size.width * shown / 100))
                }
                .frame(height: thickness)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard geometry.size.width > 0 else { return }
                            let next = min(max(value.location.x / geometry.size.width, 0), 1) * 100
                            dragLevel = next
                            onChange(next)
                        }
                        .onEnded { _ in dragLevel = nil }
                )
            }
            .frame(width: 76, height: 16)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
        .help("Volume \(Int(shown.rounded()))%")
    }

    private static func symbol(for level: Double) -> String {
        switch level {
        case ..<1: "speaker.slash.fill"
        case ..<34: "speaker.wave.1.fill"
        case ..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Where the volume slider would be, while NeoNotch may not press anything yet.
struct PermissionPill: View {
    @ObservedObject var music: MusicModel
    let source: MusicSource

    var body: some View {
        let denied = music.permissions[source] == .denied
        Button {
            music.requestPermission(for: source)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: denied ? "lock.fill" : "hand.tap.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(denied ? "Turn on in Settings" : "Allow controls")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(NotchTheme.fillSelected))
            .foregroundStyle(NotchTheme.primary)
        }
        .buttonStyle(PressScaleStyle())
        .help(denied
            ? "NeoNotch is switched off for \(source.displayName) under Privacy & Security → Automation."
            : "macOS asks once whether NeoNotch may control \(source.displayName).")
    }
}

// MARK: - Nothing playing

private struct MusicIdleView: View {
    @ObservedObject var music: MusicModel

    /// The first running player macOS has not let us talk to, if any.
    private var blocked: (source: MusicSource, permission: AutomationPermission)? {
        for source in music.runningSources {
            let permission = music.permissions[source] ?? .unknown
            if permission == .denied || permission == .notDetermined {
                return (source, permission)
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(NotchTheme.fill)
                    .frame(width: 46, height: 46)
                Image(systemName: blocked == nil ? "music.note" : "lock.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(NotchTheme.secondary)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 340)

            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if let blocked {
            return blocked.permission == .denied
                ? "NeoNotch can't reach \(blocked.source.displayName)"
                : "Connect \(blocked.source.displayName)"
        }
        if let running = music.runningSources.first {
            return "\(running.displayName) is open"
        }
        return "Nothing playing"
    }

    private var subtitle: String {
        if let blocked {
            return blocked.permission == .denied
                ? "Songs still show up here as they start. To use the controls, switch NeoNotch on for \(blocked.source.displayName) under Privacy & Security → Automation."
                : "Songs show up here as soon as they start. Allow access once to see what's already playing and to use the controls."
        }
        if music.runningSources.isEmpty {
            return "Play something in Spotify or Apple Music and it appears here."
        }
        return "Press play and it shows up here."
    }

    @ViewBuilder
    private var actions: some View {
        if let blocked {
            Button(blocked.permission == .denied ? "Open Settings" : "Allow Access") {
                music.requestPermission(for: blocked.source)
            }
            .buttonStyle(NotchPillButtonStyle(prominent: true))
        } else if music.runningSources.isEmpty, !music.installedSources.isEmpty {
            HStack(spacing: 8) {
                ForEach(music.installedSources) { source in
                    Button {
                        music.openPlayer(source)
                    } label: {
                        HStack(spacing: 6) {
                            if let icon = source.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(source.displayName)
                        }
                    }
                    .buttonStyle(NotchPillButtonStyle())
                }
            }
        }
    }
}
