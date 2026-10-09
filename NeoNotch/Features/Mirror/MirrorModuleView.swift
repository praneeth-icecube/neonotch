import SwiftUI

/// The camera mirror: a camera glyph until clicked, then a round live
/// preview. Stops itself the moment it leaves the screen.
struct MirrorModuleView: View {
    @ObservedObject var mirror: MirrorModel
    @ObservedObject var preferences: Preferences

    private static let diameter: CGFloat = 104

    var body: some View {
        Button {
            switch mirror.state {
            case .denied: mirror.openPrivacySettings()
            case .noCamera: break
            default: withAnimation(.notchSpring) { mirror.toggle() }
            }
        } label: {
            ZStack {
                if mirror.isLive {
                    live.transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    idle.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onAppear { mirror.appeared() }
        .onDisappear { mirror.disappeared() }
    }

    private var live: some View {
        ZStack {
            Circle().fill(NotchTheme.fill)
            if mirror.state == .live {
                CameraPreview(previewLayer: mirror.previewLayer, mirrored: preferences.mirrorFlip)
                    .clipShape(Circle())
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .overlay(Circle().strokeBorder(NotchTheme.stroke, lineWidth: 0.5))
    }

    private var idle: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(NotchTheme.primary)
                .frame(height: 38)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var symbol: String {
        switch mirror.state {
        case .denied, .noCamera: "video.slash"
        default: "web.camera"
        }
    }

    private var label: String {
        switch mirror.state {
        case .denied: "Camera is off"
        case .noCamera: "No camera"
        default: "Mirror"
        }
    }

    private var help: String {
        switch mirror.state {
        case .live, .starting: "Turn the mirror off"
        case .denied: "Allow NeoNotch to use the camera in Privacy & Security"
        case .noCamera: "No camera is connected"
        case .off: "Check yourself before a call"
        }
    }
}
