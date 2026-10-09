import SwiftUI

/// The open panel: a tab strip on top, the selected feature below.
struct ExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @Namespace private var tabHighlight
    /// The tab under the pointer. It becomes the selected tab only once the
    /// pointer has rested there for `hoverDwell`.
    @State private var hoveredTab: NotchTab?

    /// Hovering a tab switches to it. At 2 pt apart the slightest overshoot
    /// landed on the neighbour and switched to that instead — aiming for
    /// Clipboard got you Music. The gap between tabs belongs to neither.
    private static let tabSpacing: CGFloat = 12
    private static let tabSize = CGSize(width: 40, height: 26)
    /// Long enough that crossing a tab on the way somewhere else — diagonally
    /// down into the panel, say — leaves it alone; short enough that resting
    /// on one still switches at once.
    private static let hoverDwell: Duration = .milliseconds(150)

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 2) {
            HStack(spacing: Self.tabSpacing) {
                ForEach(NotchTab.strip) { tab in
                    tabButton(tab)
                }
            }
            // A new hovered tab cancels the wait for the previous one.
            .task(id: hoveredTab) {
                guard let tab = hoveredTab else { return }
                try? await Task.sleep(for: Self.hoverDwell)
                guard !Task.isCancelled else { return }
                withAnimation(.notchSpring) { viewModel.select(tab) }
            }

            Spacer(minLength: 8)

            if viewModel.preferences.showBattery {
                BatteryCapsule(battery: viewModel.battery)
                    .padding(.trailing, 6)
            }

            // Click only — no `onHover`, so settings never opens just because
            // the pointer crossed it on the way somewhere else.
            NotchIconButton(
                systemName: "gearshape.fill",
                help: viewModel.isShowingSettings ? "Back" : "Settings",
                isActive: viewModel.isShowingSettings
            ) {
                withAnimation(.notchSpring) { viewModel.toggleSettings() }
            }

            NotchIconButton(
                systemName: viewModel.isPinned ? "pin.fill" : "pin",
                help: viewModel.isPinned ? "Unpin" : "Keep open",
                isActive: viewModel.isPinned,
                activeTint: .yellow
            ) {
                viewModel.isPinned.toggle()
            }

            NotchIconButton(systemName: "xmark", help: "Close") {
                viewModel.isPinned = false
                withAnimation(.notchSpring) { viewModel.close() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    /// Icons only: the highlight slides between them, and the
    /// title is one hover away as a tooltip. A click switches at once; a hover
    /// brightens the icon straight away and switches once the pointer rests.
    private func tabButton(_ tab: NotchTab) -> some View {
        let isSelected = viewModel.tab == tab
        let isHovered = hoveredTab == tab
        return Button {
            withAnimation(.notchSpring) { viewModel.select(tab) }
        } label: {
            tabIcon(tab, isSelected: isSelected)
                .frame(width: Self.tabSize.width, height: Self.tabSize.height)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NotchTheme.fillSelected)
                            .matchedGeometryEffect(id: "tab", in: tabHighlight)
                    }
                }
                .foregroundStyle(isSelected ? NotchTheme.primary : (isHovered ? NotchTheme.secondary : NotchTheme.tertiary))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering {
                    hoveredTab = tab
                } else if hoveredTab == tab {
                    // Only if nothing else has claimed it: moving straight
                    // onto another tab can report that one first.
                    hoveredTab = nil
                }
            }
        }
        .help(tab.title)
    }

    /// While something plays, the Music tab's note becomes live level bars in
    /// the cover's colour — you can see it is playing from any tab.
    @ViewBuilder
    private func tabIcon(_ tab: NotchTab, isSelected: Bool) -> some View {
        if tab == .music, viewModel.music.isPlaying {
            AudioBars(
                isAnimating: true,
                tint: isSelected ? NotchTheme.primary : viewModel.music.palette.accentColor,
                barCount: 3,
                barWidth: 2.5,
                spacing: 2,
                minHeight: 3,
                maxHeight: 12
            )
        } else {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .semibold))
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.tab {
        case .home:
            HomeView(viewModel: viewModel, preferences: viewModel.preferences)
        case .shelf:
            ShelfView(viewModel: viewModel)
        case .clipboard:
            ClipboardView(viewModel: viewModel)
        case .music:
            MusicView(viewModel: viewModel)
        case .timer:
            TimerView(viewModel: viewModel)
        case .play:
            PlayView(viewModel: viewModel)
        case .settings:
            NotchSettingsView(preferences: viewModel.preferences, clock: viewModel.timers.clock)
        }
    }
}

// MARK: - Shared chrome

/// The area a tab draws in.
///
/// It used to be a translucent grey card. Content now sits straight on the
/// black and sections are split with `NotchDivider` — boxes inside a black
/// island read as clutter, and the panel is too small to spend on them.
struct PanelCard<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(NotchTheme.fill)
                    .frame(width: 42, height: 42)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NotchTheme.secondary)
            }
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTheme.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
