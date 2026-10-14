import ServiceManagement

/// Thin wrapper over SMAppService so the UI reflects what macOS actually has registered,
/// not just the value saved in config.json.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Registered with macOS, even if the user still has to approve it in System Settings.
    static var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled { try SMAppService.mainApp.register() }
        } else if isRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    /// The saved setting can survive while macOS drops the registration (OS upgrade, app moved or
    /// replaced, failed register()). Re-register at launch when the user wants it on.
    static func restoreIfNeeded(wanted: Bool) {
        guard wanted, status == .notRegistered || status == .notFound else { return }
        try? SMAppService.mainApp.register()
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
