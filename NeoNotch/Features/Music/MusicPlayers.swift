import AppKit
import CoreServices

// MARK: - Players

/// A media app NeoNotch can read and drive.
enum MusicSource: String, CaseIterable, Identifiable {
    case spotify
    case appleMusic

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    /// Posted by the player itself on every play, pause and track change.
    ///
    /// These are ordinary distributed notifications: receiving them needs no
    /// permission at all, which is what lets the notch notice playback the
    /// moment it starts rather than on the next poll.
    var broadcastName: Notification.Name {
        switch self {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var isInstalled: Bool { applicationURL != nil }

    /// The player's own icon, worn as a badge on the cover. Cached: asking
    /// Launch Services for an icon on every redraw is not free.
    var icon: NSImage? {
        if let cached = Self.icons[self] { return cached }
        guard let url = applicationURL else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.icons[self] = icon
        return icon
    }

    private static var icons: [MusicSource: NSImage] = [:]
}

enum PlaybackState: Equatable {
    case playing, paused, stopped

    init(report: String) {
        switch report.lowercased() {
        case "playing": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    /// Seconds. Zero when the player does not say, as with radio streams.
    var duration: Double
    /// The player's own identifier when it offers one (a Spotify URI, a Music
    /// persistent ID), otherwise the tags. Decides "is this still the same song".
    var id: String
    /// Spotify hands out a direct cover URL over Apple Events.
    var artworkURL: URL?
    /// A Spotify ad rather than a song. See `MusicSource.labellingAdvertisement`.
    var isAdvertisement = false

    init(
        title: String,
        artist: String,
        album: String,
        duration: Double,
        id: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.artworkURL = artworkURL
        if let id, !id.isEmpty {
            self.id = id
        } else {
            self.id = [title, artist, album].joined(separator: "|")
        }
    }

    /// "Artist — Album", or whichever of the two exists.
    func subtitle(fallback: String) -> String {
        let parts = [artist, album].filter { !$0.isEmpty }
        return parts.isEmpty ? fallback : parts.joined(separator: " — ")
    }
}

/// Where playback is, anchored to a moment in time, so a view can work out the
/// position for whichever frame it is drawing without the model ticking.
struct PlaybackClock: Equatable {
    /// Seconds into the track at `anchor`.
    var position: Double
    var anchor: Date
    var isRunning: Bool

    static let zero = PlaybackClock(position: 0, anchor: .distantPast, isRunning: false)

    func position(at date: Date = Date()) -> Double {
        guard isRunning else { return position }
        return position + max(0, date.timeIntervalSince(anchor))
    }

    /// Replacing the clock republishes the whole island, so a fresh reading
    /// that agrees with the running one is not worth a redraw.
    func agrees(with other: PlaybackClock, at date: Date = Date()) -> Bool {
        isRunning == other.isRunning && abs(position(at: date) - other.position(at: date)) < 0.75
    }
}

/// One report from a player, from either channel.
struct PlayerSnapshot {
    var state: PlaybackState
    var track: NowPlayingTrack?
    /// Seconds into the track when the report was made; nil if it did not say.
    var position: Double?
    /// 0…100; nil if the report did not say. Broadcasts never do.
    var volume: Double?
    var receivedAt: Date

    /// The running position, worked out by `merged(onto:)`.
    var clock = PlaybackClock.zero
    /// When this player last went from not playing to playing. The newest
    /// player to start wins when two are playing at once.
    var playingSince = Date.distantPast
    /// Last moment this player was seen playing. Decides between two paused
    /// players, so a track paused a minute ago beats one left from yesterday.
    var lastPlayedAt = Date.distantPast

    /// Folds this report onto the previous one from the same player, keeping
    /// whatever this one did not carry: a broadcast has no volume, and a
    /// Music broadcast has no position.
    func merged(onto previous: PlayerSnapshot?) -> PlayerSnapshot {
        var result = self
        let sameTrack = track != nil && previous?.track?.id == track?.id

        if result.volume == nil { result.volume = previous?.volume }
        if sameTrack, let previousTrack = previous?.track {
            if result.track?.artworkURL == nil { result.track?.artworkURL = previousTrack.artworkURL }
            if result.track?.duration == 0 { result.track?.duration = previousTrack.duration }
        }

        let isPlaying = state == .playing
        let position: Double
        if let reported = self.position, reported.isFinite {
            position = max(0, reported)
        } else if sameTrack, let previous {
            position = previous.clock.position(at: receivedAt)
        } else {
            position = 0
        }
        result.clock = PlaybackClock(position: position, anchor: receivedAt, isRunning: isPlaying)

        if isPlaying {
            result.playingSince = previous?.state == .playing
                ? (previous?.playingSince ?? receivedAt)
                : receivedAt
            result.lastPlayedAt = receivedAt
        } else {
            result.playingSince = previous?.playingSince ?? .distantPast
            result.lastPlayedAt = previous?.lastPlayedAt ?? .distantPast
        }
        return result
    }
}

// MARK: - Advertisements

extension MusicSource {
    /// Spotify plays ads through the same channels as songs, titled with the
    /// ad's button text — "Learn More" — which is what the notch showed as if
    /// it were a song. Ads are shown as "Advertisement" instead.
    func labellingAdvertisement(_ track: NowPlayingTrack) -> NowPlayingTrack {
        guard self == .spotify, Self.isAdvertisement(track) else { return track }
        var ad = track
        ad.isAdvertisement = true
        ad.title = "Advertisement"
        // Keep the sponsor's name if the ad gives one; drop button text.
        let sponsor = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        ad.artist = Self.adButtonTitles.contains(sponsor.lowercased()) ? "" : sponsor
        ad.album = ""
        return ad
    }

    /// Ads carry a `spotify:ad:…` URI where a song has `spotify:track:…`.
    /// Should a reply come without the URI, the button text gives it away —
    /// but only when there is no song URI either, so a real song that happens
    /// to be called "Learn More" is left alone.
    static func isAdvertisement(_ track: NowPlayingTrack) -> Bool {
        let id = track.id.lowercased()
        if id.hasPrefix("spotify:ad") { return true }
        let isSong = ["spotify:track:", "spotify:episode:", "spotify:local:"].contains { id.hasPrefix($0) }
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !isSong && adButtonTitles.contains(title)
    }

    private static let adButtonTitles: Set<String> = ["learn more", "advertisement", "spotify advertisement"]
}

// MARK: - Broadcasts

extension MusicSource {
    /// Reads a playback broadcast.
    ///
    /// Both players report durations here in milliseconds (Spotify's Apple
    /// Events do too; Music's Apple Events use seconds). Spotify also includes
    /// the position; Music does not.
    func snapshot(fromBroadcast info: [AnyHashable: Any], at date: Date) -> PlayerSnapshot {
        let state = PlaybackState(report: Self.text(info["Player State"]) ?? "")
        guard state != .stopped else {
            return PlayerSnapshot(state: .stopped, track: nil, position: nil, volume: nil, receivedAt: date)
        }

        let durationValue: Double?
        let position: Double?
        let identifier: String?
        switch self {
        case .spotify:
            durationValue = Self.number(info["Duration"])
            position = Self.number(info["Playback Position"])
            identifier = Self.text(info["Track ID"])
        case .appleMusic:
            durationValue = Self.number(info["Total Time"])
            position = Self.number(info["Player Position"]) ?? Self.number(info["Playback Position"])
            identifier = Self.musicPersistentID(info["PersistentID"] ?? info["Persistent ID"])
        }

        let track = labellingAdvertisement(NowPlayingTrack(
            title: Self.text(info["Name"]) ?? "",
            artist: Self.text(info["Artist"]) ?? "",
            album: Self.text(info["Album"]) ?? "",
            duration: Self.seconds(fromMilliseconds: durationValue),
            id: identifier
        ))
        return PlayerSnapshot(state: state, track: track, position: position, volume: nil, receivedAt: date)
    }

    /// Milliseconds to seconds, tolerating a player that already sent seconds:
    /// a real track shorter than a second and a half does not happen.
    private static func seconds(fromMilliseconds value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else { return 0 }
        let seconds = value / 1000
        return seconds < 1.5 ? value : seconds
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string.isEmpty ? nil : string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }

    /// Music's persistent ID arrives as a signed 64-bit number in broadcasts
    /// and as 16 hex digits over Apple Events. Normalised to hex so both
    /// channels agree on which track is which.
    static func musicPersistentID(_ value: Any?) -> String? {
        switch value {
        case let number as NSNumber:
            return String(UInt64(bitPattern: number.int64Value), radix: 16, uppercase: true)
        case let string as String:
            if let parsed = UInt64(string, radix: 16) {
                return String(parsed, radix: 16, uppercase: true)
            }
            if let parsed = Int64(string) {
                return String(UInt64(bitPattern: parsed), radix: 16, uppercase: true)
            }
            return string.isEmpty ? nil : string
        default:
            return nil
        }
    }
}

/// Listens for the players' own playback broadcasts.
///
/// Registered with `.deliverImmediately`, and that is load-bearing: AppKit
/// suspends distributed notification delivery while an app is inactive, and an
/// agent app like this one is inactive nearly all the time. With the default
/// behaviour every broadcast would sit in a queue until the next time you
/// happened to click the notch.
final class PlayerBroadcastObserver: NSObject {
    private let handler: (MusicSource, [AnyHashable: Any]) -> Void

    init(handler: @escaping (MusicSource, [AnyHashable: Any]) -> Void) {
        self.handler = handler
        super.init()
        let center = DistributedNotificationCenter.default()
        for source in MusicSource.allCases {
            center.addObserver(
                self,
                selector: #selector(received(_:)),
                name: source.broadcastName,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func received(_ note: Notification) {
        guard let source = MusicSource.allCases.first(where: { $0.broadcastName == note.name }) else { return }
        let info = note.userInfo ?? [:]
        if Thread.isMainThread {
            handler(source, info)
        } else {
            DispatchQueue.main.async { self.handler(source, info) }
        }
    }
}

// MARK: - Apple Events

/// Everything that talks to a player over Apple Events.
///
/// Only ever called from the model's script queue: `NSAppleScript` must not
/// run on two threads at once. Every script checks `is running` first, because
/// `tell application` on a player that has just quit would relaunch it.
enum PlayerBridge {
    enum Command {
        case playPause, next, previous
        case seek(Double)
        case volume(Double)

        fileprivate var verb: String {
            switch self {
            case .playPause: "playpause"
            case .next: "next track"
            case .previous: "previous track"
            // `String(format:)` is not localised, so this is always a dot.
            case .seek(let seconds): "set player position to \(String(format: "%.2f", max(0, seconds)))"
            case .volume(let level): "set sound volume to \(Int(min(max(level, 0), 100).rounded()))"
            }
        }

        /// Fixed scripts are compiled once; parameterised ones every time.
        fileprivate var isCacheable: Bool {
            switch self {
            case .playPause, .next, .previous: true
            case .seek, .volume: false
            }
        }
    }

    /// The player's full state in one round trip.
    static func query(_ source: MusicSource) -> Result<PlayerSnapshot, AppleScriptError> {
        let reply: NSAppleEventDescriptor
        switch AppleScriptRunner.execute(statusScript(for: source), cache: true) {
        case .failure(let error): return .failure(error)
        case .success(let descriptor): reply = descriptor
        }

        func item(_ index: Int) -> NSAppleEventDescriptor? {
            reply.numberOfItems >= index ? reply.atIndex(index) : nil
        }
        func string(_ index: Int) -> String {
            item(index)?.stringValue ?? ""
        }

        let stateText = string(1)
        if stateText == "notrunning" { return .failure(.notRunning) }

        let now = Date()
        let rawVolume = item(7)?.doubleValue ?? -1
        let volume: Double? = rawVolume >= 0 ? rawVolume : nil
        let state = PlaybackState(report: stateText)
        guard state != .stopped else {
            return .success(PlayerSnapshot(state: .stopped, track: nil, position: nil, volume: volume, receivedAt: now))
        }

        let rawDuration = item(5)?.doubleValue ?? 0
        let identifier: String? = switch source {
        case .spotify: string(8)
        case .appleMusic: MusicSource.musicPersistentID(string(8))
        }
        let artworkURL = string(9)
        let track = source.labellingAdvertisement(NowPlayingTrack(
            title: string(2),
            artist: string(3),
            album: string(4),
            // Spotify's Apple Events report milliseconds, Music's report seconds.
            duration: source == .spotify ? rawDuration / 1000 : rawDuration,
            id: identifier,
            artworkURL: artworkURL.isEmpty ? nil : URL(string: artworkURL)
        ))
        return .success(PlayerSnapshot(
            state: state,
            track: track,
            position: item(6)?.doubleValue,
            volume: volume,
            receivedAt: now
        ))
    }

    static func send(_ command: Command, to source: MusicSource) -> Result<Void, AppleScriptError> {
        AppleScriptRunner.execute(commandScript(command, for: source), cache: command.isCacheable)
            .map { _ in () }
    }

    static func commandScript(_ command: Command, for source: MusicSource) -> String {
        """
        if running of application id "\(source.bundleID)" then
            with timeout of 3 seconds
                tell application id "\(source.bundleID)" to \(command.verb)
            end timeout
        end if
        """
    }

    /// The cover embedded in Music's current track, with the track's ID so a
    /// song that changed mid-request is not given the wrong picture.
    static func appleMusicArtwork() -> (id: String?, data: Data)? {
        guard case .success(let reply) = AppleScriptRunner.execute(appleMusicArtworkScript, cache: true),
              reply.numberOfItems >= 2,
              let artwork = reply.atIndex(2),
              artwork.descriptorType != typeType
        else { return nil }
        let data = artwork.data
        guard data.count > 16 else { return nil }
        return (MusicSource.musicPersistentID(reply.atIndex(1)?.stringValue), data)
    }

    static let appleMusicArtworkScript = """
        if not (running of application id "com.apple.Music") then return {"", missing value}
        with timeout of 4 seconds
            tell application id "com.apple.Music"
                try
                    set nnTrack to current track
                    return {(persistent ID of nnTrack) as text, raw data of artwork 1 of nnTrack}
                end try
            end tell
        end timeout
        return {"", missing value}
        """

    /// Player state is compared against the player's own constants rather
    /// than coerced to text, and every field is read inside its own `try`: one
    /// missing value (ads, podcasts, radio) must not lose the whole reply.
    ///
    /// Every variable carries an `nn` prefix, and that is not decoration.
    /// AppleScript reserves some short words — `st`, as in `1st`, is one — and
    /// a script using one fails to compile. The first version of this script
    /// kept the player state in `st`, so every query died before it reached
    /// the player and the notch showed "Nothing playing" whatever was on.
    /// `--selftest-music` compiles these scripts to keep that from recurring.
    static func statusScript(for source: MusicSource) -> String {
        let fields: String
        switch source {
        case .spotify:
            fields = """
                        try
                            set nnID to (id of nnTrack) as text
                        end try
                        try
                            set nnCover to (artwork url of nnTrack) as text
                        end try
            """
        case .appleMusic:
            fields = """
                        try
                            set nnID to (persistent ID of nnTrack) as text
                        end try
            """
        }
        let streamTitle = source == .appleMusic
            ? """
                    try
                        if nnTitle is "" then set nnTitle to (current stream title) as text
                    end try
            """
            : ""

        return """
        if not (running of application id "\(source.bundleID)") then return {"notrunning"}
        with timeout of 3 seconds
            tell application id "\(source.bundleID)"
                set nnState to "stopped"
                try
                    if player state is playing then
                        set nnState to "playing"
                    else if player state is paused then
                        set nnState to "paused"
                    end if
                end try
                set nnVolume to -1
                try
                    set nnVolume to sound volume
                end try
                if nnState is "stopped" then return {nnState, "", "", "", 0, 0, nnVolume, "", ""}
                set nnTitle to ""
                set nnArtist to ""
                set nnAlbum to ""
                set nnDuration to 0
                set nnPosition to 0
                set nnID to ""
                set nnCover to ""
                try
                    set nnTrack to current track
                    try
                        set nnTitle to (name of nnTrack) as text
                    end try
                    try
                        set nnArtist to (artist of nnTrack) as text
                    end try
                    try
                        set nnAlbum to (album of nnTrack) as text
                    end try
                    try
                        set nnDuration to duration of nnTrack
                    end try
        \(fields)
                end try
        \(streamTitle)
                try
                    set nnPosition to player position
                end try
                return {nnState, nnTitle, nnArtist, nnAlbum, nnDuration, nnPosition, nnVolume, nnID, nnCover}
            end tell
        end timeout
        """
    }
}

enum AppleScriptError: Error, Equatable {
    /// -1743: the user said no, in the dialog or in System Settings.
    case permissionDenied
    /// -1744: macOS has not asked yet, and was told not to.
    case consentRequired
    /// -600, -609: the player is not running, or quit mid-conversation.
    case notRunning
    case compileFailed
    case failed(Int)

    init(code: Int) {
        switch code {
        case -1743: self = .permissionDenied
        case -1744: self = .consentRequired
        case -600, -609: self = .notRunning
        default: self = .failed(code)
        }
    }
}

enum AppleScriptRunner {
    /// Compiled once and run many times. Only touched from the script queue.
    private static var compiled: [String: NSAppleScript] = [:]

    /// Compiles without running — checks syntax and resolves every term
    /// against the player's dictionary. Nil when it compiles.
    static func compileError(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return "could not create script" }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            let message = error?[NSAppleScript.errorMessage] as? String ?? "unknown error"
            let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
            return "\(message) (\(code))"
        }
        return nil
    }

    static func execute(_ source: String, cache: Bool = false) -> Result<NSAppleEventDescriptor, AppleScriptError> {
        let script: NSAppleScript
        if let hit = compiled[source] {
            script = hit
        } else {
            guard let fresh = NSAppleScript(source: source) else { return .failure(.compileFailed) }
            var compileError: NSDictionary?
            guard fresh.compileAndReturnError(&compileError) else {
                Trace.log("music", "compile failed: \(compileError ?? [:])")
                return .failure(.compileFailed)
            }
            if cache { compiled[source] = fresh }
            script = fresh
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return .failure(AppleScriptError(code: code))
        }
        return .success(result)
    }
}

// MARK: - Automation permission

/// Where NeoNotch stands with macOS on controlling a given player.
enum AutomationPermission: Equatable {
    case unknown
    case granted
    /// macOS has never asked. The first Apple Event would show the dialog.
    case notDetermined
    case denied
    case playerNotRunning
}

enum Automation {
    /// Asks macOS about Automation access to a player without sending it an
    /// event. With `prompt`, shows the system dialog if it has never been
    /// answered — and then blocks until it is, so never call that on main.
    static func status(of source: MusicSource, prompt: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID)
        guard let descriptor = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, prompt)
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventNotPermitted: return .denied
        case errAEEventWouldRequireUserConsent: return .notDetermined
        case procNotFound: return .playerNotRunning
        default:
            Trace.log("music", "automation status for \(source.displayName): \(status)")
            return .unknown
        }
    }

    /// Privacy & Security → Automation, where a "Don't Allow" can be undone.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}
