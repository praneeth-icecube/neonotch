import AppKit

/// Exercises the drop read path without needing a real drag.
///
/// A real drag cannot be simulated without Accessibility permission, so this
/// covers the half that is ours: given a pasteboard shaped exactly like the one
/// Finder hands over, does a file actually land on the shelf?
///
///     NeoNotch.app/Contents/MacOS/NeoNotch --selftest-drop /etc/hosts
@MainActor
enum DropSelfTest {
    static let flag = "--selftest-drop"

    static func requestedPaths() -> [String]? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let paths = Array(arguments.dropFirst(index + 1))
        return paths.isEmpty ? ["/etc/hosts"] : paths
    }

    static func run(paths: [String]) -> Int32 {
        let shelf = ShelfModel()
        let before = shelf.items.count
        var failures = 0

        // 1. A file drag, exactly as Finder writes it.
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let filePasteboard = NSPasteboard(name: .init("NeoNotchSelfTestFiles"))
        filePasteboard.clearContents()
        filePasteboard.writeObjects(urls as [NSURL])
        let fileAccepted = shelf.accept(pasteboard: filePasteboard)
        let fileAdded = shelf.items.count - before
        report("file drop", ok: fileAccepted && fileAdded == urls.count,
               detail: "accepted=\(fileAccepted) added=\(fileAdded)/\(urls.count)", &failures)

        // 2. Dropping the same files again must not duplicate them.
        let countBeforeRepeat = shelf.items.count
        _ = shelf.accept(pasteboard: filePasteboard)
        report("duplicate drop ignored", ok: shelf.items.count == countBeforeRepeat,
               detail: "count \(countBeforeRepeat) -> \(shelf.items.count)", &failures)

        // 3. Text becomes a staged .txt file that can be dragged back out.
        let textPasteboard = NSPasteboard(name: .init("NeoNotchSelfTestText"))
        textPasteboard.clearContents()
        textPasteboard.setString("dropped from the pasteboard", forType: .string)
        let countBeforeText = shelf.items.count
        let textAccepted = shelf.accept(pasteboard: textPasteboard)
        let staged = shelf.items.last
        let stagedOK = textAccepted
            && shelf.items.count == countBeforeText + 1
            && staged?.isStaged == true
            && staged.map { FileManager.default.fileExists(atPath: $0.url.path) } == true
        report("text drop staged to file", ok: stagedOK,
               detail: staged.map { "\($0.url.lastPathComponent)" } ?? "nothing staged", &failures)

        // 4. The type match behind early drag detection. `isDragInFlight` also
        //    requires a held button and a change in the pasteboard, neither of
        //    which can be faked here, so test the half that can silently break:
        //    does a Finder-shaped pasteboard match our accepted types?
        //
        //    Deliberately a private pasteboard. An earlier version wrote to the
        //    real `.drag` pasteboard, which left the system primed with file
        //    URLs and made every subsequent click look like a file drag.
        let dragPasteboard = NSPasteboard(name: .init("NeoNotchSelfTestDrag"))
        dragPasteboard.clearContents()
        dragPasteboard.writeObjects(urls as [NSURL])
        let matched = dragPasteboard.availableType(from: NotchDragTypes.accepted)
        report("drag pasteboard matches accepted types", ok: matched != nil,
               detail: matched?.rawValue ?? "no match — early drag detection would never fire",
               &failures)

        // 5. The truth table for early drag detection. Case one is the
        //    regression that made the notch fly open on every click.
        let cases: [(String, Bool, Int, Int, Bool, Bool)] = [
            ("click, stale drag pasteboard", true,  7, 7, true,  false),
            ("real drag of a file",          true,  8, 7, true,  true),
            ("drag of a type we refuse",     true,  8, 7, false, false),
            ("no button held",               false, 8, 7, true,  false)
        ]
        for (name, down, change, idle, hasType, want) in cases {
            let got = NotchDragTypes.dragInFlight(
                buttonDown: down,
                changeCount: change,
                idleChangeCount: idle,
                hasAcceptedType: hasType
            )
            report("drag detection: \(name)", ok: got == want,
                   detail: "got \(got), want \(want)", &failures)
        }

        // Leave nothing behind.
        shelf.clear()

        print(failures == 0 ? "drop self-test PASSED" : "drop self-test FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    private static func report(_ name: String, ok: Bool, detail: String, _ failures: inout Int) {
        print("  [\(ok ? "pass" : "FAIL")] \(name) — \(detail)")
        if !ok { failures += 1 }
    }
}
