import AppKit
import SwiftUI

/// The launcher: two columns of icon tiles and a plus at the end.
/// Click to open; right-click to remove or reorder.
struct BookmarksModuleView: View {
    @ObservedObject var bookmarks: BookmarksModel
    var onAdd: () -> Void

    static let tile: CGFloat = 30
    private static let gap: CGFloat = 8
    private let columns = [
        GridItem(.fixed(tile), spacing: gap),
        GridItem(.fixed(tile), spacing: gap)
    ]

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: Self.gap) {
                    ForEach(bookmarks.bookmarks) { bookmark in
                        BookmarkTile(bookmark: bookmark, icon: bookmarks.icons[bookmark.id]) {
                            bookmarks.open(bookmark)
                        }
                        .contextMenu {
                            Button("Open \(bookmark.name)") { bookmarks.open(bookmark) }
                            Divider()
                            Button("Move Earlier") { bookmarks.move(bookmark, by: -1) }
                            Button("Move Later") { bookmarks.move(bookmark, by: 1) }
                            Divider()
                            Button("Remove", role: .destructive) {
                                withAnimation(.notchSpring) { bookmarks.remove(bookmark) }
                            }
                        }
                    }
                    AddBookmarkTile(action: onAdd)
                }
                // Centred while it fits, scrolling once it does not.
                .frame(minHeight: geometry.size.height)
            }
        }
    }
}

private struct BookmarkTile: View {
    let bookmark: Bookmark
    let icon: NSImage?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? NotchTheme.fillSelected : NotchTheme.fill)
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: bookmark.kind == .app ? 26 : 19, height: bookmark.kind == .app ? 26 : 19)
                        .clipShape(RoundedRectangle(cornerRadius: bookmark.kind == .app ? 0 : 4, style: .continuous))
                } else {
                    Text(bookmark.initial)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(NotchTheme.secondary)
                }
            }
            .frame(width: BookmarksModuleView.tile, height: BookmarksModuleView.tile)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(bookmark.name)
    }
}

private struct AddBookmarkTile: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? NotchTheme.fillHover : NotchTheme.fill)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHovering ? NotchTheme.primary : NotchTheme.secondary)
            }
            .frame(width: BookmarksModuleView.tile, height: BookmarksModuleView.tile)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("Add a site or an app")
    }
}

/// The little form the plus opens: paste a link, or pick an app.
struct AddBookmarkCard: View {
    @ObservedObject var bookmarks: BookmarksModel
    var onClose: () -> Void

    @State private var text = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Add bookmark")
                .font(.system(size: 12, weight: .semibold))
            TextField("Paste a link or type a site", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NotchTheme.fill))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isInvalid ? Color.red.opacity(0.7) : .clear, lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit(add)
                .onChange(of: text) { isInvalid = false }
            HStack(spacing: 6) {
                Button("Choose App…") {
                    bookmarks.chooseApp()
                    onClose()
                }
                .buttonStyle(NotchPillButtonStyle(compact: true))
                Spacer(minLength: 4)
                Button("Cancel", action: onClose)
                    .buttonStyle(NotchPillButtonStyle(compact: true))
                Button("Add", action: add)
                    .buttonStyle(NotchPillButtonStyle(prominent: true, compact: true))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
        .notchCard()
        .onAppear { isFocused = true }
    }

    private func add() {
        if bookmarks.add(text) {
            onClose()
        } else {
            withAnimation(.easeOut(duration: 0.15)) { isInvalid = true }
        }
    }
}
