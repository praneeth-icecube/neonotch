import AppKit
import SwiftUI

/// Colours pulled from the current cover, so the notch can wear the album.
struct ArtworkPalette: Equatable {
    /// Vivid and bright enough to read on black: level bars, highlights.
    var accent: NSColor
    /// The cover's overall cast, for glows and washes.
    var average: NSColor

    static let neutral = ArtworkPalette(
        accent: NSColor(white: 0.86, alpha: 1),
        average: NSColor(white: 0.35, alpha: 1)
    )

    var accentColor: Color { Color(nsColor: accent) }
    var averageColor: Color { Color(nsColor: average) }

    /// Buckets a 24×24 thumbnail by hue and takes the bucket with the most
    /// vivid, bright pixels — the colour you would name if asked what colour
    /// the cover is, which a plain average (usually a muddy brown) is not.
    static func extract(from image: NSImage) -> ArtworkPalette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return .neutral }

        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .neutral }

        struct Bucket { var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0 }
        var buckets = [Bucket](repeating: Bucket(), count: 12)
        var total = (red: 0.0, green: 0.0, blue: 0.0)

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            total.red += red
            total.green += green
            total.blue += blue

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
            guard saturation > 0.22, maximum > 0.22 else { continue }

            let hue = Self.hue(red: red, green: green, blue: blue, maximum: maximum, minimum: minimum)
            let index = min(11, Int(hue * 12))
            let weight = saturation * maximum * maximum
            buckets[index].red += red * weight
            buckets[index].green += green * weight
            buckets[index].blue += blue * weight
            buckets[index].weight += weight
        }

        let count = Double(side * side)
        let average = NSColor(
            srgbRed: total.red / count,
            green: total.green / count,
            blue: total.blue / count,
            alpha: 1
        )

        // A near-greyscale cover has no colour worth wearing; stay neutral
        // rather than inventing a tint out of noise.
        guard let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 2 else {
            return ArtworkPalette(accent: neutral.accent, average: average)
        }
        let raw = NSColor(
            srgbRed: best.red / best.weight,
            green: best.green / best.weight,
            blue: best.blue / best.weight,
            alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        raw.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Lifted so it reads on black, held back from neon.
        let accent = NSColor(
            hue: hue,
            saturation: min(max(saturation, 0.42), 0.78),
            brightness: max(brightness, 0.88),
            alpha: 1
        )
        return ArtworkPalette(accent: accent, average: average)
    }

    private static func hue(red: Double, green: Double, blue: Double, maximum: Double, minimum: Double) -> Double {
        let delta = maximum - minimum
        guard delta > 0 else { return 0 }
        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta
        } else if maximum == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue /= 6
        return hue < 0 ? hue + 1 : hue
    }
}

/// Finds a cover for a track from the most exact source available.
///
/// First the player itself over Apple Events, which is exact but needs
/// Automation permission. Then a public lookup that needs none: Spotify's own
/// oEmbed endpoint for Spotify tracks, the iTunes Search API for Apple Music.
/// Those send the track's ID or its artist and album to the company whose
/// catalogue it is already in.
final class ArtworkLoader {
    struct Cover {
        let image: NSImage
        let palette: ArtworkPalette
    }

    private var cache: [String: Cover] = [:]
    private var order: [String] = []
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    /// Main thread only.
    func cached(_ id: String) -> Cover? { cache[id] }

    /// Completes on the main thread, with nil if nothing turned up.
    func load(
        track: NowPlayingTrack,
        source: MusicSource,
        canAskPlayer: Bool,
        scriptQueue: DispatchQueue,
        completion: @escaping (Cover?) -> Void
    ) {
        Task { [session] in
            let image = await Self.fetch(
                track: track,
                source: source,
                canAskPlayer: canAskPlayer,
                scriptQueue: scriptQueue,
                session: session
            )
            let cover = image.map { Cover(image: $0, palette: ArtworkPalette.extract(from: $0)) }
            await MainActor.run {
                if let cover { self.store(cover, for: track.id) }
                completion(cover)
            }
        }
    }

    private func store(_ cover: Cover, for id: String) {
        if cache[id] == nil { order.append(id) }
        cache[id] = cover
        while order.count > 24 {
            cache[order.removeFirst()] = nil
        }
    }

    // MARK: Sources

    private static func fetch(
        track: NowPlayingTrack,
        source: MusicSource,
        canAskPlayer: Bool,
        scriptQueue: DispatchQueue,
        session: URLSession
    ) async -> NSImage? {
        switch source {
        case .spotify:
            if let url = track.artworkURL, let image = await download(url, session: session) {
                return image
            }
            if let url = await spotifyOEmbedCover(for: track.id, session: session),
               let image = await download(url, session: session) {
                return image
            }
            return nil

        case .appleMusic:
            if canAskPlayer {
                let embedded = await withCheckedContinuation { continuation in
                    scriptQueue.async { continuation.resume(returning: PlayerBridge.appleMusicArtwork()) }
                }
                if let embedded, embedded.id == nil || embedded.id == track.id,
                   let image = NSImage(data: embedded.data) {
                    return image
                }
            }
            if let url = await iTunesCover(for: track, session: session),
               let image = await download(url, session: session) {
                return image
            }
            return nil
        }
    }

    /// `https://open.spotify.com/oembed?url=spotify:track:…` answers with a
    /// `thumbnail_url` for any public track or episode, no account needed.
    private static func spotifyOEmbedCover(for id: String, session: URLSession) async -> URL? {
        guard id.hasPrefix("spotify:track:") || id.hasPrefix("spotify:episode:"),
              var components = URLComponents(string: "https://open.spotify.com/oembed")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: id)]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thumbnail = json["thumbnail_url"] as? String
        else { return nil }
        return URL(string: thumbnail)
    }

    /// Searches by artist and album (or title), and trusts a result only if
    /// its artist matches, so a common album name does not fetch a stranger.
    private static func iTunesCover(for track: NowPlayingTrack, session: URLSession) async -> URL? {
        let artist = track.artist.trimmingCharacters(in: .whitespaces)
        let subject = track.album.isEmpty ? track.title : track.album
        guard !artist.isEmpty || !subject.isEmpty,
              var components = URLComponents(string: "https://itunes.apple.com/search")
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: [artist, subject].filter { !$0.isEmpty }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: track.album.isEmpty ? "song" : "album"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return nil }

        let wanted = artist.lowercased()
        let match = results.first { result in
            guard !wanted.isEmpty, let name = (result["artistName"] as? String)?.lowercased() else { return false }
            return name.contains(wanted) || wanted.contains(name)
        } ?? (wanted.isEmpty ? results.first : nil)

        guard let small = match?["artworkUrl100"] as? String else { return nil }
        return URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }

    private static func download(_ url: URL, session: URLSession) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return NSImage(data: data)
    }
}
