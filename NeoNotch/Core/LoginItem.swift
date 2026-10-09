import ServiceManagement

/// Launch-at-login, backed by `SMAppService`.
///
/// The registration lives in the system's login-items database rather than in
/// our own preferences, so the toggle reads from `SMAppService` instead of
/// caching a copy that could drift out of sync with System Settings.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state, which is not always what was asked for:
    /// the user can have the item disabled in System Settings, and macOS will
    /// report `.requiresApproval` until they turn it back on there.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> SMAppService.Status {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Trace.log("login", "failed to \(enabled ? "register" : "unregister"): \(error)")
        }
        return SMAppService.mainApp.status
    }
}
