import AVFoundation
import AppKit
import SwiftUI

/// The camera as a mirror, for a quick look before a call.
///
/// Off unless you click it, and switched off again the moment the widget goes
/// out of view — the notch closing, another tab — so the camera light never
/// stays on for something you are not looking at.
final class MirrorModel: ObservableObject {
    enum State: Equatable {
        case off, starting, live
        /// Camera access was refused; the widget offers the settings pane.
        case denied
        case noCamera
    }

    @Published private(set) var state: State = .off

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.praneeth.NeoNotch.mirror")
    private var isConfigured = false
    /// Whether the widget is on screen. The camera only runs while it is.
    private var isVisible = false
    private var runtimeErrorObserver: NSObjectProtocol?

    /// One preview layer for the life of the app, handed to whichever view is
    /// showing the mirror.
    ///
    /// Each view used to make its own. The first one worked; once the session
    /// had been stopped — the notch closing — a new layer attached to it on the
    /// next open showed nothing, so the mirror came back as an empty circle.
    private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    var isLive: Bool { state == .live || state == .starting }

    init() {
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            Trace.log("mirror", "runtime error: \(error?.localizedDescription ?? "unknown")")
            // Back to the camera glyph, so a click starts it afresh instead of
            // leaving a dead circle on screen.
            guard let self, self.isLive else { return }
            self.stop()
        }
    }

    deinit {
        runtimeErrorObserver.map(NotificationCenter.default.removeObserver)
    }

    func toggle() {
        isLive ? stop() : start()
    }

    func appeared() {
        isVisible = true
    }

    func disappeared() {
        isVisible = false
        stop()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            state = .starting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted else {
                        self.state = .denied
                        return
                    }
                    // Answering the prompt usually takes the pointer out of the
                    // notch, which closes the panel. The camera used to switch
                    // on anyway, with nothing on screen to show it or turn it off.
                    if self.state == .starting { self.run() }
                }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        guard state != .off, state != .denied, state != .noCamera else { return }
        state = .off
        Trace.log("mirror", "stopping")
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    private func run() {
        guard isVisible else {
            state = .off
            return
        }
        state = .starting
        queue.async { [weak self] in
            guard let self else { return }
            guard self.configureIfNeeded() else {
                DispatchQueue.main.async { self.state = .noCamera }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async {
                // Stopped, or scrolled out of view, while starting up: honour that.
                guard self.state == .starting, self.isVisible else {
                    self.queue.async { if self.session.isRunning { self.session.stopRunning() } }
                    return
                }
                Trace.log("mirror", "session running=\(running)")
                // A camera that would not start shows the glyph again rather
                // than an empty circle.
                self.state = running ? .live : .off
            }
        }
    }

    /// On the capture queue.
    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        let device = AVCaptureDevice.default(for: .video)
            ?? AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: .unspecified
            ).devices.first
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        isConfigured = !session.inputs.isEmpty
        return isConfigured
    }
}

/// Live camera preview: hosts the model's one preview layer while on screen.
struct CameraPreview: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    var mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(previewLayer: previewLayer)
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.setMirrored(mirrored)
    }

    static func dismantleNSView(_ view: PreviewView, coordinator: ()) {
        view.releaseLayer()
    }

    final class PreviewView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            // Newest view wins: if an old one is still fading out, the layer
            // moves here.
            previewLayer.removeFromSuperlayer()
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// Gives the layer up, unless a newer view has already taken it.
        func releaseLayer() {
            if previewLayer.superlayer === layer { previewLayer.removeFromSuperlayer() }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }

        func setMirrored(_ mirrored: Bool) {
            guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The connection exists once the layer is live in a window.
            DispatchQueue.main.async { [weak self] in
                self?.setMirrored(Preferences.shared.mirrorFlip)
            }
        }
    }
}
