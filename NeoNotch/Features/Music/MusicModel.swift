import AppKit
import Combine

/// What is playing in Spotify or Apple Music, and the controls for it.
///
/// Two channels feed it:
///
/// - **Broadcasts.** Both players post a distributed notification on every
///   play, pause and track change. Receiving them needs no permission and they
///   arrive the instant anything happens, so they are what makes the notch
///   notice playback at all. See `PlayerBroadcastObserver`.
/// - **Apple Events.** Controls, the exact position, volume and the embedded
///   cover need Automation permission. Once granted, a light poll keeps
///   position and volume honest. Until then the broadcasts alone still drive
///   the notch — you just cannot press anything.
///
/// The first version only had the second channel, so whenever the permission
/// was missing, pending or quietly reset by a rebuild, the notch saw nothing.
final class MusicModel: ObservableObject {
    @Published private(set) var source: MusicSource?
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var clock = PlaybackClock.zero
    /// 0…100, or nil until a player we may ask has told us.
    @Published private(set) var volume: Double?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette = ArtworkPalette.neutral
    @Published private(set) var permissions: [MusicSource: AutomationPermission] = [:]
    /// Whether the closed island shows the live activity. Stays on for a
    /// moment after playback pauses, so a quick pause or a track change does
    /// not make the island jump in and out.
    @Published private(set) var isLive = false

    static let pollInterval: TimeInterval = 2.5
    static let pauseLinger: TimeInterval = 2.5

    private let scriptQueue = DispatchQueue(label: "com.praneeth.NeoNotch.music.events", qos: .userInitiated)
    /// Separate from `scriptQueue`: the permission dialog blocks its caller
    /// until answered, and polling must not stall behind it.
    private let permissionQueue = DispatchQueue(label: "com.praneeth.NeoNotch.music.permission", qos: .userInitiated)

    private var snapshots: [MusicSource: PlayerSnapshot] = [:]
    private var broadcasts: PlayerBroadcastObserver?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var isUpdating = false
    private var isPolling = false
    private var pollAgain = false
    private var lastCommandAt: [MusicSource: Date] = [:]
    private var promptedThisLaunch: Set<MusicSource> = []
    private var checksInFlight: Set<MusicSource> = []
    private var lastPermissionSweep = Date.distantPast
    private var lingerWork: DispatchWorkItem?
    private var pendingVolume: DispatchWorkItem?
    private var lastVolumeSentAt = Date.distantPast
    private let artworkLoader = ArtworkLoader()
    private var artworkTrackID: String?
    private var artworkAttempt: String?

    init(live: Bool = true) {
        if live { start() }
    }

    deinit {
        pollTimer?.invalidate()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func start() {
        guard !isUpdating else { return }
        isUpdating = true

        broadcasts = PlayerBroadcastObserver { [weak self] source, info in
            self?.receive(info, from: source)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in self?.playerLaunched(note) },
            workspace.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in self?.playerQuit(note) }
        ]

        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        pollTimer?.tolerance = 0.5

        checkPermissions(prompt: true)
        refresh()
    }

    func stop() {
        isUpdating = false
        pollTimer?.invalidate()
        pollTimer = nil
        broadcasts = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
    }

    // MARK: What the views ask

    /// Permission for the player currently showing.
    var permission: AutomationPermission {
        source.flatMap { permissions[$0] } ?? .unknown
    }

    var canControl: Bool { permission == .granted }

    var runningSources: [MusicSource] { MusicSource.allCases.filter(\.isRunning) }

    var installedSources: [MusicSource] { MusicSource.allCases.filter(\.isInstalled) }

    /// Called when the Music tab appears: the moment accuracy matters most.
    func panelDidAppear() {
        refresh()
        if Date().timeIntervalSince(lastPermissionSweep) > 2 {
            checkPermissions(prompt: false)
        }
    }

    // MARK: Broadcasts

    private func receive(_ info: [AnyHashable: Any], from source: MusicSource) {
        guard isUpdating else { return }
        let report = source.snapshot(fromBroadcast: info, at: Date())
        Trace.log("music", "broadcast \(source.displayName): \(report.state) "
            + "\(report.track.map { "\($0.title) — \($0.artist)" } ?? "")")
        snapshots[source] = report.merged(onto: snapshots[source])
        recompute()

        switch permissions[source] {
        case .granted?:
            // Top up what the broadcast did not carry: volume, the cover URL,
            // and the position for Music.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
        case nil, .unknown?, .playerNotRunning?:
            checkPermission(for: source, prompt: true)
        case .notDetermined?, .denied?:
            break
        }
    }

    // MARK: Players coming and going

    private func musicSource(of note: Notification) -> MusicSource? {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return MusicSource.allCases.first { $0.bundleID == app?.bundleIdentifier }
    }

    private func playerLaunched(_ note: Notification) {
        guard let source = musicSource(of: note) else { return }
        // Give the player a moment to finish launching before asking it anything.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.checkPermission(for: source, prompt: true)
            self?.refresh()
        }
    }

    private func playerQuit(_ note: Notification) {
        guard let source = musicSource(of: note) else { return }
        snapshots[source] = nil
        recompute()
    }

    // MARK: Polling

    private func tick() {
        refresh()
        // Notice a permission switched on in System Settings, without a relaunch.
        if Date().timeIntervalSince(lastPermissionSweep) > 10,
           runningSources.contains(where: { permissions[$0] != .granted }) {
            checkPermissions(prompt: false)
        }
    }

    /// Asks every running player we are allowed to ask for its full state:
    /// one Apple Event each, off the main thread.
    func refresh() {
        guard isUpdating else { return }
        for source in MusicSource.allCases where snapshots[source] != nil && !source.isRunning {
            snapshots[source] = nil
        }

        let targets = MusicSource.allCases.filter { $0.isRunning && permissions[$0] == .granted }
        guard !targets.isEmpty else {
            recompute()
            return
        }
        guard !isPolling else {
            pollAgain = true
            return
        }

        isPolling = true
        let startedAt = Date()
        scriptQueue.async { [weak self] in
            let results = targets.map { ($0, PlayerBridge.query($0)) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPolling = false
                for (source, result) in results {
                    self.absorb(result, from: source, startedAt: startedAt)
                }
                self.recompute()
                if self.pollAgain {
                    self.pollAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func absorb(_ result: Result<PlayerSnapshot, AppleScriptError>, from source: MusicSource, startedAt: Date) {
        switch result {
        case .success(let report):
            // A reading taken before our own command landed would undo the
            // optimistic update and make the button flicker back.
            if let sent = lastCommandAt[source], sent > startedAt { return }
            snapshots[source] = report.merged(onto: snapshots[source])
        case .failure(.permissionDenied):
            setPermission(.denied, for: source)
        case .failure(.consentRequired):
            setPermission(.notDetermined, for: source)
        case .failure(.notRunning):
            snapshots[source] = nil
        case .failure(let error):
            // Transient (a timeout, a player mid-launch): keep what the
            // broadcasts told us rather than blanking the notch.
            Trace.log("music", "\(source.displayName) query failed: \(error)")
        }
    }

    // MARK: Choosing what to show

    private func recompute() {
        let candidates = snapshots.filter { $0.value.state != .stopped && $0.value.track != nil }
        let playing = candidates.filter { $0.value.state == .playing }
        let chosen = playing.max { $0.value.playingSince < $1.value.playingSince }
            ?? candidates.max { lhs, rhs in
                // The most recently played wins; on a tie, stay put.
                if lhs.value.lastPlayedAt != rhs.value.lastPlayedAt {
                    return lhs.value.lastPlayedAt < rhs.value.lastPlayedAt
                }
                return rhs.key == source
            }
        publish(chosen?.key, chosen?.value)
    }

    /// Assigns only what changed: every assignment republishes the island.
    private func publish(_ newSource: MusicSource?, _ snapshot: PlayerSnapshot?) {
        if source != newSource || track?.id != snapshot?.track?.id || isPlaying != (snapshot?.state == .playing) {
            Trace.log("music", "showing \(newSource?.displayName ?? "nothing")"
                + (snapshot.map { " \($0.state == .playing ? "playing" : "paused"): \($0.track?.title ?? "")" } ?? "")
                + (snapshot?.track.map { " [\($0.id)]" } ?? ""))
        }
        if source != newSource { source = newSource }
        if track != snapshot?.track { track = snapshot?.track }

        let playing = snapshot?.state == .playing
        if isPlaying != playing { isPlaying = playing }

        let newClock = snapshot?.clock ?? .zero
        if !clock.agrees(with: newClock) { clock = newClock }

        if volume != snapshot?.volume { volume = snapshot?.volume }

        updateLive(playing: playing, hasTrack: snapshot != nil)
        loadArtworkIfNeeded()
    }

    private func updateLive(playing: Bool, hasTrack: Bool) {
        if playing {
            lingerWork?.cancel()
            lingerWork = nil
            if !isLive { isLive = true }
            return
        }
        guard isLive else { return }
        guard hasTrack else {
            lingerWork?.cancel()
            lingerWork = nil
            isLive = false
            return
        }
        guard lingerWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lingerWork = nil
            if !self.isPlaying { self.isLive = false }
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseLinger, execute: work)
    }

    // MARK: Artwork

    private func loadArtworkIfNeeded() {
        guard isUpdating else { return }
        guard let source, let track else {
            if artwork != nil { artwork = nil }
            artworkTrackID = nil
            artworkAttempt = nil
            return
        }

        if track.id != artworkTrackID {
            artworkTrackID = track.id
            artworkAttempt = nil
            // Never show the last song's cover on this one, even briefly.
            if let hit = artworkLoader.cached(track.id) {
                artwork = hit.image
                if palette != hit.palette { palette = hit.palette }
                return
            }
            if artwork != nil { artwork = nil }
        }
        guard artwork == nil else { return }

        // Try again whenever a better source turns up: a direct URL from the
        // player, or permission to ask it for the embedded cover.
        let canAskPlayer = permissions[source] == .granted
        let attempt = "\(track.artworkURL?.absoluteString ?? "")|\(canAskPlayer)"
        guard attempt != artworkAttempt else { return }
        artworkAttempt = attempt

        let id = track.id
        artworkLoader.load(
            track: track,
            source: source,
            canAskPlayer: canAskPlayer,
            scriptQueue: scriptQueue
        ) { [weak self] cover in
            guard let self, self.track?.id == id else { return }
            guard let cover else {
                if self.palette != .neutral { self.palette = .neutral }
                return
            }
            self.artwork = cover.image
            if self.palette != cover.palette { self.palette = cover.palette }
        }
    }

    // MARK: Permission

    /// Asks macOS where each running player stands. With `prompt`, a player
    /// macOS has never asked about gets the system dialog — once per launch,
    /// so declining is not met with the same question on every poll.
    func checkPermissions(prompt: Bool) {
        lastPermissionSweep = Date()
        for source in runningSources {
            checkPermission(for: source, prompt: prompt)
        }
    }

    private func checkPermission(for source: MusicSource, prompt: Bool) {
        guard isUpdating, source.isRunning, !checksInFlight.contains(source) else { return }
        checksInFlight.insert(source)
        permissionQueue.async { [weak self] in
            let status = Automation.status(of: source, prompt: false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.checksInFlight.remove(source)
                self.setPermission(status, for: source)
                if status == .notDetermined, prompt, !self.promptedThisLaunch.contains(source) {
                    self.requestPermission(for: source)
                }
            }
        }
    }

    private func setPermission(_ status: AutomationPermission, for source: MusicSource) {
        // A player that quit tells us nothing about the permission itself.
        guard status != .playerNotRunning || permissions[source] == nil else { return }
        let previous = permissions[source]
        guard previous != status else { return }
        permissions[source] = status
        Trace.log("music", "\(source.displayName) automation: \(status)")
        if status == .granted {
            refresh()
            loadArtworkIfNeeded()
        }
    }

    /// Shows the system Automation dialog for a player — or, if it was already
    /// declined, opens the settings pane where that can be undone. `then` runs
    /// once access is granted, so a tap on play is not lost to the dialog.
    func requestPermission(for requested: MusicSource? = nil, then action: (() -> Void)? = nil) {
        guard let source = requested ?? source ?? runningSources.first else { return }
        if permissions[source] == .denied {
            Automation.openSettings()
            return
        }
        promptedThisLaunch.insert(source)
        permissionQueue.async { [weak self] in
            let status = Automation.status(of: source, prompt: true)
            DispatchQueue.main.async {
                guard let self else { return }
                self.setPermission(status, for: source)
                if status == .granted { action?() }
            }
        }
    }

    // MARK: Controls

    func playPause() { perform(.playPause) }
    func nextTrack() { perform(.next) }
    func previousTrack() { perform(.previous) }

    func seek(to seconds: Double) {
        let duration = track?.duration ?? 0
        perform(.seek(duration > 0 ? min(max(seconds, 0), duration) : max(seconds, 0)))
    }

    /// Called continuously while the volume slider is dragged; sends at most
    /// one Apple Event per 80 ms and always the final value.
    func setVolume(_ level: Double) {
        guard let source else { return }
        let clamped = min(max(level, 0), 100)
        if var snapshot = snapshots[source] {
            snapshot.volume = clamped
            snapshots[source] = snapshot
        }
        if volume != clamped { volume = clamped }

        pendingVolume?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingVolume = nil
            self.lastVolumeSentAt = Date()
            self.perform(.volume(clamped))
        }
        pendingVolume = work
        let wait = max(0, 0.08 - Date().timeIntervalSince(lastVolumeSentAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    func openPlayer(_ requested: MusicSource? = nil) {
        guard let target = requested ?? source, let url = target.applicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func perform(_ command: PlayerBridge.Command) {
        guard let source = source ?? runningSources.first else { return }
        guard permissions[source] == .granted else {
            // The first press of a control is as good a moment as any to ask.
            requestPermission(for: source) { [weak self] in self?.perform(command) }
            return
        }

        applyOptimistically(command, to: source)
        lastCommandAt[source] = Date()
        scriptQueue.async { [weak self] in
            let result = PlayerBridge.send(command, to: source)
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failure(let error) = result {
                    Trace.log("music", "\(source.displayName) command failed: \(error)")
                    if error == .permissionDenied { self.setPermission(.denied, for: source) }
                }
                // Let the player settle, then read back what actually happened.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
            }
        }
    }

    /// The tap shows up now; the read-back confirms it a moment later.
    private func applyOptimistically(_ command: PlayerBridge.Command, to source: MusicSource) {
        guard var snapshot = snapshots[source] else { return }
        let now = Date()
        switch command {
        case .playPause:
            let position = snapshot.clock.position(at: now)
            snapshot.state = snapshot.state == .playing ? .paused : .playing
            snapshot.clock = PlaybackClock(position: position, anchor: now, isRunning: snapshot.state == .playing)
            if snapshot.state == .playing {
                snapshot.playingSince = now
                snapshot.lastPlayedAt = now
            }
        case .seek(let seconds):
            snapshot.clock = PlaybackClock(position: seconds, anchor: now, isRunning: snapshot.state == .playing)
        case .volume(let level):
            snapshot.volume = level
        case .next, .previous:
            return
        }
        snapshots[source] = snapshot
        recompute()
    }

    // MARK: Debug

    #if DEBUG
    /// Used by `Snapshotter`; stops live updates so nothing overwrites the seed.
    func debugApply(
        track: NowPlayingTrack?,
        playing: Bool,
        source: MusicSource?,
        position: Double = 0,
        artwork: NSImage? = nil,
        permission: AutomationPermission = .granted,
        volume: Double? = 64
    ) {
        stop()
        lingerWork?.cancel()
        lingerWork = nil
        snapshots = [:]
        permissions = source.map { [$0: permission] } ?? [:]
        self.source = track == nil ? nil : source
        self.track = track
        self.isPlaying = playing && track != nil
        self.clock = PlaybackClock(position: position, anchor: Date(), isRunning: false)
        self.volume = track == nil ? nil : volume
        self.artwork = artwork
        self.palette = artwork.map(ArtworkPalette.extract(from:)) ?? .neutral
        self.isLive = playing && track != nil
    }
    #endif
}
