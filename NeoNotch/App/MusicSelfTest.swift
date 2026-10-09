import AppKit

/// Exercises the music pipeline without needing anything to be playing.
///
/// A player cannot be made to play from here, so this covers the parts that are
/// ours and can silently break: reading broadcasts shaped exactly like
/// Spotify's and Music's, the clock rules that keep the scrubber honest, every
/// Apple Event script compiling against the player's real dictionary, the
/// permission API, and the permission-free cover lookups. If NeoNotch may
/// already talk to a running player, it also asks that player for its state.
///
///     open -n -W --stdout /tmp/music.txt -a NeoNotch.app --args --selftest-music
///
/// Launch it through `open` as above. macOS files Automation permission under
/// the app that launched a process, so started from a terminal the permission
/// lines describe the terminal's access, not NeoNotch's. Add `--offline` to
/// skip the two network lookups.
@MainActor
enum MusicSelfTest {
    static let flag = "--selftest-music"

    static var isRequested: Bool { CommandLine.arguments.contains(flag) }

    static func run() -> Int32 {
        var failures = 0
        let now = Date()

        // 1. Spotify's broadcast: milliseconds, a position, a track URI.
        let spotify = MusicSource.spotify.snapshot(fromBroadcast: [
            "Player State": "Playing",
            "Name": "Mr. Brightside",
            "Artist": "The Killers",
            "Album": "Hot Fuss",
            "Track ID": "spotify:track:3n3Ppam7vgaVa1iaRUc9Lp",
            "Duration": NSNumber(value: 222_973),
            "Playback Position": NSNumber(value: 41.25)
        ], at: now)
        report("spotify broadcast: state and tags",
               ok: spotify.state == .playing
                   && spotify.track?.title == "Mr. Brightside"
                   && spotify.track?.artist == "The Killers",
               detail: "\(spotify.state) \(spotify.track?.title ?? "-") — \(spotify.track?.artist ?? "-")",
               &failures)
        report("spotify broadcast: duration read as milliseconds",
               ok: abs((spotify.track?.duration ?? 0) - 222.973) < 0.001,
               detail: "\(spotify.track?.duration ?? 0) s", &failures)
        report("spotify broadcast: position and track ID",
               ok: spotify.position == 41.25 && spotify.track?.id == "spotify:track:3n3Ppam7vgaVa1iaRUc9Lp",
               detail: "position \(spotify.position ?? -1), id \(spotify.track?.id ?? "-")", &failures)

        // 2. Music's broadcast: milliseconds too, no position, and a signed
        //    persistent ID that has to match the hex Apple Events return.
        let signedID: Int64 = -4_371_921_365_128_371_215
        let music = MusicSource.appleMusic.snapshot(fromBroadcast: [
            "Player State": "Paused",
            "Name": "Blinding Lights",
            "Artist": "The Weeknd",
            "Album": "After Hours",
            "Total Time": NSNumber(value: 200_040),
            "PersistentID": NSNumber(value: signedID)
        ], at: now)
        let hexID = String(UInt64(bitPattern: signedID), radix: 16, uppercase: true)
        report("music broadcast: state, duration, no position",
               ok: music.state == .paused
                   && abs((music.track?.duration ?? 0) - 200.04) < 0.001
                   && music.position == nil,
               detail: "\(music.state), \(music.track?.duration ?? 0) s", &failures)
        report("music broadcast: persistent ID matches the Apple Events form",
               ok: music.track?.id == MusicSource.musicPersistentID(hexID)
                   && MusicSource.musicPersistentID("00" + hexID) == music.track?.id,
               detail: "\(music.track?.id ?? "-") vs \(hexID)", &failures)

        // 3. Stopped means there is nothing to show.
        let stopped = MusicSource.spotify.snapshot(fromBroadcast: ["Player State": "Stopped"], at: now)
        report("stopped broadcast clears the track",
               ok: stopped.state == .stopped && stopped.track == nil,
               detail: "\(stopped.state)", &failures)

        // 3b. Spotify ads arrive titled with their button text ("Learn More").
        let ad = MusicSource.spotify.snapshot(fromBroadcast: [
            "Player State": "Playing",
            "Name": "Learn More",
            "Artist": "",
            "Album": "",
            "Track ID": "spotify:ad:000000012c9a7c83000000205f0e2dbb",
            "Duration": NSNumber(value: 30_000)
        ], at: now)
        report("spotify ad (by its spotify:ad: URI) shows as Advertisement",
               ok: ad.track?.title == "Advertisement" && ad.track?.isAdvertisement == true,
               detail: "\(ad.track?.title ?? "-") — \(ad.track?.subtitle(fallback: "Spotify") ?? "-")", &failures)
        let adWithoutURI = MusicSource.spotify.labellingAdvertisement(
            NowPlayingTrack(title: "Learn More", artist: "", album: "", duration: 30))
        report("spotify ad without a URI shows as Advertisement",
               ok: adWithoutURI.isAdvertisement && adWithoutURI.title == "Advertisement",
               detail: adWithoutURI.title, &failures)
        let songCalledLearnMore = MusicSource.spotify.labellingAdvertisement(NowPlayingTrack(
            title: "Learn More", artist: "Some Band", album: "Some Album", duration: 200, id: "spotify:track:abc"))
        report("a real song called Learn More is left alone",
               ok: !songCalledLearnMore.isAdvertisement && songCalledLearnMore.title == "Learn More",
               detail: songCalledLearnMore.title, &failures)
        let musicTrack = MusicSource.appleMusic.labellingAdvertisement(
            NowPlayingTrack(title: "Learn More", artist: "", album: "", duration: 30))
        report("Apple Music tracks are never labelled ads", ok: !musicTrack.isAdvertisement,
               detail: musicTrack.title, &failures)

        // 4. Clock rules. A report without a position keeps the same track
        //    running from the last reading; a pause freezes it; a new track
        //    starts from zero.
        let track = NowPlayingTrack(title: "A", artist: "B", album: "C", duration: 300, id: "t1")
        let first = PlayerSnapshot(state: .playing, track: track, position: 30, volume: 50, receivedAt: now)
            .merged(onto: nil)
        let later = now.addingTimeInterval(10)
        let second = PlayerSnapshot(state: .playing, track: track, position: nil, volume: nil, receivedAt: later)
            .merged(onto: first)
        report("clock carries across a report with no position",
               ok: abs(second.clock.position(at: later) - 40) < 0.01 && second.volume == 50,
               detail: "10 s later: \(second.clock.position(at: later)) s, volume \(second.volume ?? -1)",
               &failures)
        let pausedAt = later.addingTimeInterval(5)
        let paused = PlayerSnapshot(state: .paused, track: track, position: nil, volume: nil, receivedAt: pausedAt)
            .merged(onto: second)
        let aMinuteLater = paused.clock.position(at: pausedAt.addingTimeInterval(60))
        report("pause freezes the clock", ok: abs(aMinuteLater - 45) < 0.01,
               detail: "a minute after pausing: \(aMinuteLater) s", &failures)
        let other = NowPlayingTrack(title: "D", artist: "E", album: "F", duration: 200, id: "t2")
        let next = PlayerSnapshot(state: .playing, track: other, position: nil, volume: nil, receivedAt: pausedAt)
            .merged(onto: paused)
        report("a new track starts from zero",
               ok: next.clock.position == 0 && next.playingSince == pausedAt,
               detail: "position \(next.clock.position)", &failures)

        // 5. Palette: a vivid cover lends its hue; a grey one stays neutral.
        let redAccent = ArtworkPalette.extract(from: solidImage(NSColor(srgbRed: 0.85, green: 0.1, blue: 0.15, alpha: 1)))
            .accent.usingColorSpace(.sRGB)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        redAccent?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        report("palette: a vivid cover lends its hue",
               ok: (hue < 0.05 || hue > 0.95) && saturation > 0.4 && brightness > 0.8,
               detail: String(format: "hue %.2f, saturation %.2f, brightness %.2f", hue, saturation, brightness),
               &failures)
        let greyAccent = ArtworkPalette.extract(from: solidImage(NSColor(white: 0.5, alpha: 1))).accent
        report("palette: a grey cover stays neutral", ok: greyAccent == ArtworkPalette.neutral.accent,
               detail: "\(greyAccent)", &failures)

        // 6. Every Apple Event script compiles against the player's own
        //    dictionary. This catches a typo before it turns into a notch that
        //    quietly never updates. Compiling reads the dictionary from the app
        //    bundle; it does not launch the player.
        let commands: [(String, PlayerBridge.Command)] = [
            ("play/pause", .playPause), ("next", .next), ("previous", .previous),
            ("seek", .seek(12.5)), ("volume", .volume(40))
        ]
        for source in MusicSource.allCases where source.isInstalled {
            var scripts = [("status", PlayerBridge.statusScript(for: source))]
            scripts += commands.map { ($0.0, PlayerBridge.commandScript($0.1, for: source)) }
            if source == .appleMusic {
                scripts.append(("artwork", PlayerBridge.appleMusicArtworkScript))
            }
            for (name, script) in scripts {
                let error = AppleScriptRunner.compileError(script)
                report("\(source.displayName) \(name) script compiles", ok: error == nil,
                       detail: error ?? "ok", &failures)
            }
        }

        // 7. The permission API answers without prompting — `.unknown` would
        //    mean macOS rejected the question itself. 8. Where access is
        //    already granted, ask the player for the real thing.
        for source in MusicSource.allCases where source.isInstalled {
            let status = Automation.status(of: source, prompt: false)
            report("\(source.displayName) automation status", ok: status != .unknown,
                   detail: "\(status)", &failures)
            guard status == .granted else { continue }
            switch PlayerBridge.query(source) {
            case .success(let live):
                let what = live.track.map { "\($0.title) — \($0.artist), \(Int($0.duration)) s" } ?? "no track"
                report("\(source.displayName) live query", ok: true,
                       detail: "\(live.state): \(what), volume \(live.volume.map { "\(Int($0))" } ?? "?")",
                       &failures)
            case .failure(let error):
                report("\(source.displayName) live query", ok: false, detail: "\(error)", &failures)
            }
        }

        // 9. Covers with no permission at all, over the network.
        if !CommandLine.arguments.contains("--offline") {
            let loader = ArtworkLoader()
            let lookups: [(String, NowPlayingTrack, MusicSource)] = [
                ("Spotify oEmbed cover", NowPlayingTrack(
                    title: "Mr. Brightside", artist: "The Killers", album: "Hot Fuss",
                    duration: 223, id: "spotify:track:3n3Ppam7vgaVa1iaRUc9Lp"), .spotify),
                ("iTunes Search cover", NowPlayingTrack(
                    title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
                    duration: 200, id: hexID), .appleMusic)
            ]
            for (label, track, source) in lookups {
                var cover: ArtworkLoader.Cover?
                var finished = false
                loader.load(track: track, source: source, canAskPlayer: false, scriptQueue: .main) { result in
                    cover = result
                    finished = true
                }
                let deadline = Date().addingTimeInterval(20)
                while !finished, Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
                let detail = cover.map {
                    "\(Int($0.image.size.width))×\(Int($0.image.size.height)), accent \($0.palette.accent)"
                } ?? (finished ? "no cover found" : "timed out")
                report(label, ok: cover != nil, detail: detail, &failures)
            }
        }

        print(failures == 0 ? "music self-test PASSED" : "music self-test FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    private static func solidImage(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private static func report(_ name: String, ok: Bool, detail: String, _ failures: inout Int) {
        print("  [\(ok ? "pass" : "FAIL")] \(name) — \(detail)")
        if !ok { failures += 1 }
    }
}
