import AppKit
import SwiftUI

/// Home: every widget side by side, split by hairlines, in the
/// order chosen in Settings → Home.
struct HomeView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var preferences: Preferences

    @StateObject private var briefing = AIRequest()
    @State private var overlay: Overlay?

    private enum Overlay: Equatable {
        case briefing, addBookmark
    }

    var body: some View {
        let modules = preferences.homeModules
        ZStack(alignment: .topLeading) {
            if modules.isEmpty {
                EmptyStateView(
                    symbol: "square.grid.2x2",
                    title: "Home is empty",
                    subtitle: "Pick widgets in Settings → Home"
                )
            } else {
                row(modules)
                    .opacity(overlay == nil ? 1 : 0.3)
                    .allowsHitTesting(overlay == nil)
            }

            if let overlay {
                // Click anywhere else to dismiss.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                card(for: overlay, modules: modules)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: overlay)
        .onDisappear {
            if overlay == .addBookmark { viewModel.setTextEntry(false) }
            briefing.dismiss()
        }
    }

    private func row(_ modules: [HomeModule]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                if index > 0 {
                    NotchDivider().padding(.vertical, 2)
                }
                moduleView(module)
                    .frame(width: module.width)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, HomeModule.padding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func moduleView(_ module: HomeModule) -> some View {
        switch module {
        case .music:
            MusicModuleView(music: viewModel.music)
        case .timer:
            TimerModuleView(timers: viewModel.timers)
        case .calendar:
            CalendarModuleView(calendar: viewModel.calendar, canBrief: viewModel.isAIAvailable) {
                presentBriefing()
            }
        case .bookmarks:
            BookmarksModuleView(bookmarks: viewModel.bookmarks) {
                viewModel.setTextEntry(true)
                overlay = .addBookmark
            }
        case .reminders:
            NotesModuleView(notes: viewModel.notes, canRephrase: viewModel.isAIAvailable) { editing in
                viewModel.setTextEntry(editing)
            }
        case .notes:
            AppleNotesModuleView(composer: viewModel.appleNotes) { editing in
                viewModel.setTextEntry(editing)
            }
        case .focus:
            FocusModuleView(focus: viewModel.focus)
        case .mirror:
            MirrorModuleView(mirror: viewModel.mirror, preferences: preferences)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func card(for overlay: Overlay, modules: [HomeModule]) -> some View {
        switch overlay {
        case .addBookmark:
            AddBookmarkCard(bookmarks: viewModel.bookmarks, onClose: close)
                .offset(x: cardOffset(over: .bookmarks, width: 260, modules: modules), y: 6)
        case .briefing:
            BriefingCard(
                request: briefing,
                day: viewModel.calendar.selectedDay,
                onRefresh: presentBriefing,
                onClose: close
            )
            .offset(x: cardOffset(over: .calendar, width: 300, modules: modules), y: 6)
        }
    }

    /// Lines a card up over its widget, kept inside the row.
    private func cardOffset(over module: HomeModule, width: CGFloat, modules: [HomeModule]) -> CGFloat {
        let rowWidth = HomeModule.rowWidth(modules)
        let start = HomeModule.offset(of: module, in: modules) ?? 0
        return min(max(0, start), max(0, rowWidth - width))
    }

    private func presentBriefing() {
        let events = viewModel.calendar.events
        let day = viewModel.calendar.selectedDay
        overlay = .briefing
        briefing.run("Daily Brief") {
            try await AIAssistant.briefing(for: events, on: day)
        }
    }

    private func close() {
        if overlay == .addBookmark { viewModel.setTextEntry(false) }
        briefing.dismiss()
        overlay = nil
    }
}

/// Apple Intelligence's read of the day: the "Daily Brief".
private struct BriefingCard: View {
    @ObservedObject var request: AIRequest
    let day: Date
    let onRefresh: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.7, blue: 1), Color(red: 0.95, green: 0.6, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Daily Brief")
                    .font(.system(size: 12, weight: .semibold))
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.tertiary)
                Spacer(minLength: 4)
                if case .done(_, let text) = request.state {
                    iconButton("doc.on.doc", help: "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                iconButton("arrow.clockwise", help: "Write it again", action: onRefresh)
                    .disabled(request.isWorking)
                iconButton("xmark", help: "Close", action: onClose)
            }

            switch request.state {
            case .idle, .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading your calendar…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .done(_, let text):
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 12))
                        .lineSpacing(2.5)
                        .foregroundStyle(NotchTheme.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
            case .failed(let reason):
                Text(reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.45))
            }
        }
        .padding(12)
        .frame(width: 300)
        .notchCard()
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(NotchTheme.fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(NotchTheme.secondary)
        .help(help)
    }
}
