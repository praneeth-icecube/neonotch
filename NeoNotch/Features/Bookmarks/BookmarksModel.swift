import AppKit
import UniformTypeIdentifiers

struct Bookmark: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case website, app }

    var id = UUID()
    var name: String
    var kind: Kind
    /// A web address, or the path of an app bundle.
    var target: String

    var url: URL? {
        switch kind {
        case .website: URL(string: target)
        case .app: URL(fileURLWithPath: target)
        }
    }

    /// The letter drawn when there is no icon yet.
    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

/// One-click launchers for sites and apps, kept in `bookmarks.json`.
///
/// Site icons come from the site itself — its `apple-touch-icon` or `icon`
/// links, then the conventional paths — never from a third-party favicon
/// service, which would learn every site you bookmark. They are cached on disk
/// so a launch does not refetch them.
final class BookmarksModel: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var icons: [UUID: NSImage] = [:]

    private static let file = "bookmarks.json"
    private let iconFolder = Storage.folder("Bookmark Icons")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        ]
        return URLSession(configuration: configuration)
    }()

    init() {
        if let saved = Storage.load([Bookmark].self, from: Self.file) {
            bookmarks = saved
        } else {
            bookmarks = Self.starters
            persist()
        }
        bookmarks.forEach(loadIcon)
    }

    /// First-run set, so the widget is useful before you add your own.
    static let starters: [Bookmark] = [
        Bookmark(name: "Google", kind: .website, target: "https://www.google.com"),
        Bookmark(name: "YouTube", kind: .website, target: "https://www.youtube.com"),
        Bookmark(name: "ChatGPT", kind: .website, target: "https://chatgpt.com"),
        Bookmark(name: "GitHub", kind: .website, target: "https://github.com")
    ]

    // MARK: Adding

    /// Takes "github.com", a full URL, or the path of an app. Returns false
    /// when the input is neither.
    @discardableResult
    func add(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix(".app"), FileManager.default.fileExists(atPath: trimmed) {
            addApp(at: URL(fileURLWithPath: trimmed))
            return true
        }
        guard let url = Self.webURL(from: trimmed) else { return false }
        append(Bookmark(name: Self.name(for: url), kind: .website, target: url.absoluteString))
        return true
    }

    func addApp(at url: URL) {
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        append(Bookmark(name: name, kind: .app, target: url.path))
    }

    /// Opens a picker in /Applications.
    func chooseApp(completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Pick apps to launch from the notch"
        panel.level = .screenSaver + 1
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            if response == .OK { panel.urls.forEach { self?.addApp(at: $0) } }
            completion?()
        }
    }

    private func append(_ bookmark: Bookmark) {
        // The same site or app twice is never what you meant.
        let identity = Self.identity(of: bookmark.target)
        guard !bookmarks.contains(where: { Self.identity(of: $0.target) == identity }) else { return }
        bookmarks.append(bookmark)
        persist()
        loadIcon(bookmark)
    }

    // MARK: Using

    func open(_ bookmark: Bookmark) {
        guard let url = bookmark.url else { return }
        switch bookmark.kind {
        case .website:
            NSWorkspace.shared.open(url)
        case .app:
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        icons[bookmark.id] = nil
        try? FileManager.default.removeItem(at: iconURL(for: bookmark))
        persist()
    }

    func move(_ bookmark: Bookmark, by step: Int) {
        guard let index = bookmarks.firstIndex(of: bookmark) else { return }
        let target = index + step
        guard bookmarks.indices.contains(target) else { return }
        bookmarks.swapAt(index, target)
        persist()
    }

    private func persist() {
        Storage.save(bookmarks, to: Self.file)
    }

    // MARK: Parsing input

    static func webURL(from text: String) -> URL? {
        let candidate = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        return url
    }

    /// "https://www.github.com/" and "github.com" are the same bookmark:
    /// compared by host without "www." and path without trailing slashes.
    static func identity(of target: String) -> String {
        guard let url = URL(string: target), let host = url.host?.lowercased() else {
            return target.lowercased()
        }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return bareHost + path + (url.query.map { "?" + $0 } ?? "")
    }

    /// "www.github.com" → "Github".
    static func name(for url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let label = host.split(separator: ".").first.map(String.init) ?? host
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    // MARK: Icons

    private func iconURL(for bookmark: Bookmark) -> URL {
        iconFolder.appendingPathComponent("\(bookmark.id.uuidString).png")
    }

    private func loadIcon(_ bookmark: Bookmark) {
        switch bookmark.kind {
        case .app:
            icons[bookmark.id] = NSWorkspace.shared.icon(forFile: bookmark.target)
        case .website:
            if let cached = NSImage(contentsOf: iconURL(for: bookmark)) {
                icons[bookmark.id] = cached
                return
            }
            guard let page = bookmark.url else { return }
            // Holds the model for the length of one fetch; it lives as long
            // as the app anyway.
            Task { [session] in
                guard let image = await Self.fetchIcon(for: page, session: session) else { return }
                await MainActor.run {
                    guard self.bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
                    self.icons[bookmark.id] = image
                    if let png = image.pngData {
                        try? png.write(to: self.iconURL(for: bookmark), options: .atomic)
                    }
                }
            }
        }
    }

    /// The site's own declared icons, biggest first, then the usual paths.
    private static func fetchIcon(for page: URL, session: URLSession) async -> NSImage? {
        var candidates: [URL] = []
        if let (data, response) = try? await session.data(from: page),
           let html = String(data: data.prefix(400_000), encoding: .utf8)
            ?? String(data: data.prefix(400_000), encoding: .isoLatin1) {
            let base = response.url ?? page
            candidates += declaredIcons(in: html, base: base)
        }
        if let root = URL(string: "/", relativeTo: page)?.absoluteURL {
            candidates += ["apple-touch-icon.png", "favicon.ico"]
                .compactMap { URL(string: $0, relativeTo: root)?.absoluteURL }
        }

        var seen = Set<URL>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard let (data, response) = try? await session.data(from: candidate),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = NSImage(data: data),
                  image.isValid, image.size.width >= 16
            else { continue }
            return image
        }
        return nil
    }

    /// `<link rel="apple-touch-icon" …>` and `<link rel="icon" sizes="…" …>`,
    /// touch icons first (they are the big, square ones), then by size.
    static func declaredIcons(in html: String, base: URL) -> [URL] {
        guard let linkPattern = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive)
        else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var found: [(url: URL, rank: Int)] = []
        for match in linkPattern.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"),
                  !rel.contains("mask"),
                  let href = attribute("href", in: tag),
                  let url = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL,
                  !url.pathExtension.lowercased().contains("svg")
            else { continue }
            let size = attribute("sizes", in: tag)
                .flatMap { $0.lowercased().split(separator: "x").first.flatMap { Int($0) } } ?? 0
            let rank = (rel.contains("apple-touch-icon") ? 10_000 : 0) + size
            found.append((url, rank))
        }
        return found.sorted { $0.rank > $1.rank }.map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag))
        else { return nil }
        for group in 2...4 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }

    #if DEBUG
    func debugUseStarters() {
        bookmarks = Self.starters
    }
    #endif
}

extension NSImage {
    /// PNG bytes, for caching an image to disk.
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
