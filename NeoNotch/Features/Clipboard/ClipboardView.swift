import AppKit
import SwiftUI

/// The clipboard: search along the top, then the history as a row of
/// cards, pinned ones first and tinted. Click a card to copy it back, drag it
/// out, or hand its text to Apple Intelligence.
struct ClipboardView: View {
    @ObservedObject var viewModel: NotchViewModel

    @StateObject private var ai = AIRequest()

    private var clipboard: ClipboardModel { viewModel.clipboard }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            NotchDivider(axis: .horizontal)
                .padding(.bottom, 9)

            if clipboard.filteredEntries.isEmpty {
                EmptyStateView(
                    symbol: "doc.on.clipboard",
                    title: clipboard.entries.isEmpty ? "Nothing copied yet" : "No matches",
                    subtitle: clipboard.entries.isEmpty ? "Copy anything and it lands here" : nil
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(clipboard.filteredEntries) { entry in
                            ClipboardCard(
                                entry: entry,
                                canUseAI: viewModel.isAIAvailable && entry.text != nil,
                                onCopy: {
                                    clipboard.copy(entry)
                                    viewModel.flash("Copied")
                                },
                                onPin: { withAnimation(.notchSpring) { clipboard.togglePin(entry) } },
                                onDelete: { withAnimation(.notchSpring) { clipboard.remove(entry) } },
                                onAI: { task in run(task, on: entry) },
                                provider: { clipboard.itemProvider(for: entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .overlay(alignment: .top) {
            if ai.state != .idle {
                AIResultCard(
                    request: ai,
                    onCopy: { text in
                        clipboard.copyText(text)
                        viewModel.flash("Copied")
                        ai.dismiss()
                    },
                    onClose: ai.dismiss
                )
                .padding(.top, 2)
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: ai.state == .idle)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.secondary)
                TextField("Search clipboard", text: Binding(
                    get: { clipboard.searchText },
                    set: { clipboard.searchText = $0 }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NotchTheme.fill))

            if clipboard.hasUnpinned {
                ClearButton {
                    withAnimation(.notchSpring) { clipboard.clear() }
                }
            }
        }
        .padding(.bottom, 7)
    }

    private func run(_ task: AITask, on entry: ClipboardEntry) {
        guard let text = entry.text else { return }
        ai.run(task.title) { try await AIAssistant.perform(task, on: text) }
    }
}

/// A plain-text "Clear", which leaves pinned cards alone.
private struct ClearButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button("Clear", action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(isHovering ? NotchTheme.primary : NotchTheme.secondary)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
            .help("Clear history — pinned items stay")
    }
}

private struct ClipboardCard: View {
    let entry: ClipboardEntry
    let canUseAI: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onAI: (AITask) -> Void
    let provider: () -> NSItemProvider

    @State private var isHovering = false

    private static let blue = Color(red: 0.29, green: 0.64, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 6)
            meta
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 164, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(entry.isPinned
                      ? Self.blue.opacity(isHovering ? 0.2 : 0.14)
                      : Color.white.opacity(isHovering ? 0.1 : 0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture(perform: onCopy)
        .onDrag(provider)
        .help("Click to copy")
    }

    @ViewBuilder
    private var content: some View {
        switch entry.payload {
        case .text:
            Text(entry.preview)
                .font(.system(size: 12, weight: .medium))
                .lineSpacing(1.5)
                .lineLimit(3)
                .foregroundStyle(NotchTheme.primary)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .files(let urls):
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: urls.first?.path ?? "/"))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.preview)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Text(entry.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.tertiary)
                }
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let icon = entry.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            Text(entry.age)
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if isHovering || entry.isPinned {
                HStack(spacing: 7) {
                    if isHovering, canUseAI {
                        Menu {
                            ForEach(AITask.allCases) { task in
                                Button {
                                    onAI(task)
                                } label: {
                                    Label(task.title, systemImage: task.symbol)
                                }
                            }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .foregroundStyle(NotchTheme.secondary)
                        .help("Apple Intelligence")
                    }
                    iconButton(entry.isPinned ? "pin.fill" : "pin", tint: entry.isPinned ? Self.blue : NotchTheme.secondary,
                               help: entry.isPinned ? "Unpin" : "Pin", action: onPin)
                    if isHovering {
                        iconButton("trash", tint: Color(red: 1, green: 0.36, blue: 0.36), help: "Delete", action: onDelete)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.85))
        .help(help)
    }
}

/// What Apple Intelligence made of a clipping, with Copy to take it.
private struct AIResultCard: View {
    @ObservedObject var request: AIRequest
    let onCopy: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                if case .done(_, let text) = request.state {
                    Button("Copy") { onCopy(text) }
                        .buttonStyle(NotchPillButtonStyle(prominent: true, compact: true))
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(NotchTheme.fill))
                }
                .buttonStyle(PressScaleStyle())
                .foregroundStyle(NotchTheme.secondary)
            }

            switch request.state {
            case .idle, .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Working on it, on this Mac…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.secondary)
                }
            case .done(_, let text):
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 70)
            case .failed(let reason):
                Text(reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.45))
            }
        }
        .padding(12)
        .frame(width: 440)
        .notchCard()
    }

    private var title: String {
        switch request.state {
        case .working(let title), .done(let title, _): title
        default: "Apple Intelligence"
        }
    }
}
