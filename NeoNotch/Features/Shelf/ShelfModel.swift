import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct ShelfItem: Identifiable {
    let id = UUID()
    let url: URL
    /// True when NeoNotch created the file (from dropped text/image), so it is
    /// ours to delete when the item is removed.
    var isStaged: Bool
    var thumbnail: NSImage?

    var name: String { url.lastPathComponent }

    var subtitle: String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
        // Bundles are directories, so check the content type before falling
        // back to "Folder" — otherwise every .app reads as a folder.
        if let type = values?.contentType {
            if type.conforms(to: .application) { return "Application" }
            if type.conforms(to: .folder) { return "Folder" }
        }
        if let size = values?.fileSize {
            return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
        if values?.isDirectory == true { return "Folder" }
        return url.pathExtension.uppercased()
    }
}

extension ShelfItem: Equatable {
    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id && lhs.thumbnail === rhs.thumbnail
    }
}

/// Holds files parked on the notch. Dropped files are referenced in place;
/// dropped text, images and links are written into a staging folder so they can
/// be dragged back out as real files.
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let defaultsKey = "shelfItems"
    private let thumbnailGenerator = QLThumbnailGenerator.shared

    private lazy var stagingDirectory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeoNotch/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    init() {
        restore()
    }

    var urls: [URL] { items.map(\.url) }

    // MARK: Adding

    /// Reads a drop straight off the pasteboard.
    ///
    /// This is the path real drags take. It is deliberately not built on
    /// `NSItemProvider`: the pasteboard tells us exactly what was dropped, in
    /// priority order, with no type negotiation in between.
    @discardableResult
    func accept(pasteboard: NSPasteboard, completion: ((Int) -> Void)? = nil) -> Bool {
        var resolved: [(url: URL, staged: Bool)] = []

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            resolved = urls.map { ($0, false) }
        } else if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
                  let image = images.first,
                  let url = stageImage(image) {
            resolved = [(url, true)]
        } else if let links = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
                  let link = links.first,
                  let url = stageLink(link) {
            resolved = [(url, true)]
        } else if let text = pasteboard.string(forType: .string),
                  let url = stageText(text) {
            resolved = [(url, true)]
        }

        Trace.log("shelf", "pasteboard types=\(pasteboard.types?.map(\.rawValue) ?? []) -> \(resolved.count) item(s)")

        guard !resolved.isEmpty else {
            completion?(0)
            return false
        }
        let added = append(resolved)
        completion?(added)
        return added > 0
    }

    /// Adds already-resolved files, skipping anything already on the shelf.
    /// Returns how many were actually new.
    @discardableResult
    private func append(_ entries: [(url: URL, staged: Bool)]) -> Int {
        let existing = Set(items.map(\.url.standardizedFileURL))
        let fresh = entries.filter { !existing.contains($0.url.standardizedFileURL) }
        for entry in fresh {
            let item = ShelfItem(url: entry.url, isStaged: entry.staged, thumbnail: nil)
            items.append(item)
            loadThumbnail(for: item)
        }
        persist()
        return fresh.count
    }

    /// Resolves every provider, then appends whatever survived. Used by the
    /// "Add…" button and by drags out of other SwiftUI views.
    func accept(providers: [NSItemProvider], completion: @escaping (Int) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var resolved: [(url: URL, staged: Bool)] = []

        func collect(_ url: URL?, staged: Bool) {
            guard let url else { return }
            lock.lock()
            resolved.append((url, staged))
            lock.unlock()
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    defer { group.leave() }
                    guard let url, url.isFileURL else { return }
                    collect(url, staged: false)
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] image, _ in
                    defer { group.leave() }
                    guard let image = image as? NSImage else { return }
                    collect(self?.stageImage(image), staged: true)
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] string, _ in
                    defer { group.leave() }
                    guard let text = string as? String else { return }
                    collect(self?.stageText(text), staged: true)
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    defer { group.leave() }
                    guard let url else { return }
                    collect(self?.stageLink(url), staged: true)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            completion(self.append(resolved))
        }
    }

    /// Opens a file picker. The plus tile in the shelf uses this, so the shelf
    /// is reachable without a drag at all.
    func promptToAdd(completion: ((Int) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add to Shelf"
        panel.message = "Pick files to park on the notch"
        panel.level = .screenSaver + 1

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self, response == .OK else {
                completion?(0)
                return
            }
            completion?(self.append(panel.urls.map { ($0, false) }))
        }
    }

    /// A drop as things to share: files as they are, a web link as a link,
    /// text and images staged to files first, the same way the shelf does.
    func sharingItems(from pasteboard: NSPasteboard) -> [Any] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first, let url = stageImage(image) {
            return [url]
        }
        if let links = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], let link = links.first {
            return [link]
        }
        if let text = pasteboard.string(forType: .string), let url = stageText(text) {
            return [url]
        }
        return []
    }

    // MARK: Removing

    func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        if removed.isStaged {
            try? FileManager.default.removeItem(at: removed.url)
        }
        persist()
    }

    func clear() {
        for item in items where item.isStaged {
            try? FileManager.default.removeItem(at: item.url)
        }
        items.removeAll()
        persist()
    }

    /// Drops entries whose file has since been moved or deleted.
    func pruneMissing() {
        let survivors = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard survivors.count != items.count else { return }
        items = survivors
        persist()
    }

    // MARK: Staging

    private func uniqueStagingURL(name: String, ext: String) -> URL {
        let stamp = Self.stampFormatter.string(from: Date())
        return stagingDirectory.appendingPathComponent("\(name) \(stamp).\(ext)")
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    private func stageImage(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let url = uniqueStagingURL(name: "Image", ext: "png")
        try? png.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func stageText(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = uniqueStagingURL(name: "Text", ext: "txt")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func stageLink(_ link: URL) -> URL? {
        let url = uniqueStagingURL(name: "Link", ext: "webloc")
        let plist: [String: Any] = ["URL": link.absoluteString]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        ) else { return nil }
        try? data.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Thumbnails

    private func loadThumbnail(for item: ShelfItem) {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 128, height: 128),
            scale: 2,
            representationTypes: .all
        )
        thumbnailGenerator.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let self else { return }
            let image = representation?.nsImage ?? NSWorkspace.shared.icon(forFile: item.url.path)
            DispatchQueue.main.async {
                guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                self.items[index].thumbnail = image
            }
        }
    }

    // MARK: Persistence

    private func persist() {
        let payload = items.map { ["path": $0.url.path, "staged": $0.isStaged] as [String: Any] }
        UserDefaults.standard.set(payload, forKey: defaultsKey)
    }

    #if DEBUG
    /// Used by `Snapshotter` and SwiftUI previews.
    func debugAppend(_ item: ShelfItem) {
        items.append(item)
    }
    #endif

    private func restore() {
        guard let payload = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: Any]] else { return }
        items = payload.compactMap { entry in
            guard let path = entry["path"] as? String,
                  FileManager.default.fileExists(atPath: path)
            else { return nil }
            return ShelfItem(
                url: URL(fileURLWithPath: path),
                isStaged: entry["staged"] as? Bool ?? false,
                thumbnail: nil
            )
        }
        for item in items { loadThumbnail(for: item) }
    }
}
