import UserNotifications

/// Posts a system notification when a timer finishes.
///
/// This exists because of the lock screen. NeoNotch cannot draw there — macOS
/// hides every user-session window behind `loginwindow`, deliberately, so that
/// no app can put its own UI next to the password field. A notification is the
/// one supported channel onto that screen, so a timer that fires while the Mac
/// is locked still reaches you.
enum TimerNotifier {
    private static var isAuthorized = false

    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                isAuthorized = granted
                if let error {
                    Trace.log("notify", "authorization failed: \(error.localizedDescription)")
                } else {
                    Trace.log("notify", "authorization granted=\(granted)")
                }
            }
    }

    static func timerFinished(label: String) {
        post(title: "Timer finished", body: label)
    }

    /// Any time-sensitive notice: a timer, the end of a focus session or break.
    static func post(title: String, body: String) {
        guard isAuthorized else {
            Trace.log("notify", "skipped, not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Trace.log("notify", "post failed: \(error.localizedDescription)")
            }
        }
    }
}
