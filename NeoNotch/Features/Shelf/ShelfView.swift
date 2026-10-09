import AppKit
import SwiftUI

/// Files parked on the notch. Drop anything onto the island to add it; drag a
/// card out to move it into Finder, Mail, a chat window — anywhere.
struct ShelfView: View {
    @ObservedObject var viewModel: NotchViewModel

    private var shelf: ShelfModel { viewModel.shelf }

    var body: some View {
        HStack(spacing: 0) {
            AirDropZone(
                isTargeted: viewModel.isAirDropTargeted,
                hasItems: !shelf.items.isEmpty,
                action: sendShelf
            )
            .frame(width: 124)
            // Reported for the drop handler, which lives in AppKit and needs
            // to know whether a drop landed here or on the shelf.
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { viewModel.airDropZone = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, frame in viewModel.airDropZone = frame }
                }
            }

            NotchDivider()
                .padding(.vertical, 8)
                .padding(.trailing, 6)

            PanelCard {
                if shelf.items.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(shelf.items) { item in
                                    ShelfCard(item: item) { shelf.remove(item) }
                                }
                                AddTile(compact: true) { add() }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 6)
                        }
                        footer
                    }
                }
            }
            .overlay {
                if viewModel.isDropTargeted && !viewModel.isAirDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
        }
        .onAppear { shelf.pruneMissing() }
        .onDisappear { viewModel.airDropZone = .zero }
    }

    private func sendShelf() {
        guard !shelf.items.isEmpty else {
            viewModel.flash("Drop files on AirDrop", style: .init(symbol: "arrow.down.circle.fill", tint: .accentColor))
            return
        }
        if !AirDrop.send(shelf.urls) {
            viewModel.flash("AirDrop is off", style: .init(symbol: "exclamationmark.circle.fill", tint: .orange))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            AddTile(compact: false) { add() }
            Text(viewModel.isDropTargeted ? "Release to drop" : "Drop files onto the notch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Text("Text, images and links become files too")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func add() {
        shelf.promptToAdd { added in
            if added > 0 { viewModel.flash("Added \(added) to shelf") }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("^[\(shelf.items.count) item](inflect: true)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))

            Spacer()

            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting(shelf.urls)
            }
            .buttonStyle(ShelfActionStyle())
            .disabled(shelf.items.isEmpty)

            Button("Clear") {
                withAnimation(.notchSpring) { shelf.clear() }
            }
            .buttonStyle(ShelfActionStyle(destructive: true))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }
}

/// The AirDrop target, at the head of the shelf. Drop anything on it
/// to send it; click it to send everything on the shelf.
private struct AirDropZone: View {
    let isTargeted: Bool
    let hasItems: Bool
    let action: () -> Void

    @State private var isHovering = false

    private static let blue = Color(red: 0.29, green: 0.64, blue: 1)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if let icon = AirDrop.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "wave.3.right.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(Self.blue)
                    }
                }
                .frame(width: 42, height: 42)
                .scaleEffect(isTargeted ? 1.14 : 1)

                Text("AirDrop")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isTargeted ? Self.blue : NotchTheme.secondary)
                Text(isTargeted ? "Release to send" : (hasItems ? "Click to send the shelf" : "Drop to send"))
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchTheme.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Self.blue.opacity(0.12) : (isHovering ? NotchTheme.fill : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Self.blue : .clear,
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("AirDrop")
    }
}

/// Dashed box with a plus. Doubles as the thing that tells you the notch takes
/// drops at all, and as a way in without dragging — it opens a file picker.
private struct AddTile: View {
    var compact: Bool
    var action: () -> Void

    @State private var isHovering = false

    private var side: CGFloat { compact ? 62 : 46 }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.10 : 0.04))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isHovering ? 0.5 : 0.25),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])
                    )
                Image(systemName: "plus")
                    .font(.system(size: compact ? 17 : 15, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.55))
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: compact ? 74 : side, alignment: .top)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("Add files to the shelf")
    }
}

private struct ShelfCard: View {
    let item: ShelfItem
    var onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Icons sit straight on the black; the tile only appears
                // under the pointer, to show what a drag or double-click takes.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovering ? NotchTheme.fillHover : .clear)
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(5)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 62, height: 62)

            Text(item.name)
                .font(.system(size: 9.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.85))
            Text(item.subtitle)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 74)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.75))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        } preview: {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail).resizable().frame(width: 64, height: 64)
            } else {
                Color.clear.frame(width: 64, height: 64)
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .help(item.url.path)
    }
}

/// The small action pill used across the panel ("Reveal", "Clear", "+1m").
struct ShelfActionStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        NotchPillButtonStyle(destructive: destructive, compact: true)
            .makeBody(configuration: configuration)
    }
}
