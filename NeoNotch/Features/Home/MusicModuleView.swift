import AppKit
import SwiftUI

/// The Home tab's player, in a compact layout: cover on the left;
/// title, artist, scrubber and transport stacked beside it.
struct MusicModuleView: View {
    @ObservedObject var music: MusicModel

    private static let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    var body: some View {
        ZStack {
            if let track = music.track, let source = music.source {
                playing(track, source: source)
                    .transition(.opacity)
            } else {
                idle
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: music.track == nil)
    }

    private func playing(_ track: NowPlayingTrack, source: MusicSource) -> some View {
        HStack(spacing: 12) {
            CoverArt(image: music.artwork, source: source, isPlaying: music.isPlaying, size: 104)
                .onTapGesture { music.openPlayer() }
                .help("Open \(source.displayName)")

            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(text: track.title.isEmpty ? source.displayName : track.title, font: Self.titleFont)
                Text(track.subtitle(fallback: source.displayName))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchTheme.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer(minLength: 8)

                PlaybackScrubber(
                    clock: music.clock,
                    duration: track.duration,
                    isPlaying: music.isPlaying,
                    onSeek: music.seek(to:)
                )

                Spacer(minLength: 4)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TransportButton(symbol: "backward.fill", size: 13, help: "Previous", action: music.previousTrack)
                    TransportButton(
                        symbol: music.isPlaying ? "pause.fill" : "play.fill",
                        size: 19,
                        help: music.isPlaying ? "Pause" : "Play",
                        action: music.playPause
                    )
                    TransportButton(symbol: "forward.fill", size: 13, help: "Next", action: music.nextTrack)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: 112)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NotchTheme.fill)
                    .frame(width: 58, height: 58)
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(NotchTheme.tertiary)
            }
            Text("Nothing playing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.secondary)
            HStack(spacing: 8) {
                ForEach(music.installedSources) { source in
                    Button {
                        music.openPlayer(source)
                    } label: {
                        Group {
                            if let icon = source.icon {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "music.note")
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(PressScaleStyle())
                    .help("Open \(source.displayName)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
