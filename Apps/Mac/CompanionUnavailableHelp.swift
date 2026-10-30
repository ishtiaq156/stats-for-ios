import AppKit

/// Displays the system-standard unavailable-Help alert with our packaged
/// application artwork explicitly assigned. The default SwiftUI Help menu
/// alert can use a generic placeholder even when the Dock icon is correct.
@MainActor
enum CompanionUnavailableHelp {
    static func show() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Help isn’t available for StatsCompanion."
        alert.addButton(withTitle: "OK")

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            alert.icon = icon
        } else if let icon = NSImage(named: "StatsBrandMark") {
            alert.icon = icon
        }

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
