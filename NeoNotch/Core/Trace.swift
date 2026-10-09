import Foundation

/// Opt-in tracing for the parts of the app that are invisible from the outside:
/// pointer tracking, hit testing, clipboard capture and Apple Event replies.
///
/// Off unless `NEONOTCH_TRACE=1` is set, so it costs nothing in normal use.
///
///     NEONOTCH_TRACE=1 NeoNotch.app/Contents/MacOS/NeoNotch
enum Trace {
    static let isEnabled = ProcessInfo.processInfo.environment["NEONOTCH_TRACE"] == "1"

    static func log(_ subsystem: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[NeoNotch/\(subsystem)] \(message())")
        fflush(stdout)
    }
}
