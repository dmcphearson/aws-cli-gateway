import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app support directory is writable
        _ = RoleManager.ensureAppSupportDirectory()

        // Ensure AWS directory permissions are correct at startup
        ConfigManager.shared.ensureDirectoryPermissions()
        
        // Sync profiles with history
        ConfigManager.shared.syncProfilesWithHistory()
        
        _ = ProfileHistoryManager.shared
        
        setupNotifications()
        setupSessionObservers()
        MenuBarManager.shared.setup()
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
            }
        }

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        ConfigManager.shared.updateIAMProfileSourceReferences()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Force save profile history before terminating
        ProfileHistoryManager.shared.persistChanges()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Only show the dialog if there's an active profile
        if MenuBarManager.shared.hasActiveSession() {
            let alert = NSAlert()
            alert.messageText = "Quit AWS SSO Gateway"
            alert.informativeText = "Would you like to clear your active SSO session cache before quitting?"
            alert.addButton(withTitle: "Quit & Clear Cache")
            alert.addButton(withTitle: "Just Quit")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn: // Quit & Clear Cache
                _ = ConfigManager.shared.clearSSOCache()
                return .terminateNow

            case .alertSecondButtonReturn: // Just Quit
                return .terminateNow

            default: // Cancel
                return .terminateCancel
            }
        }

        // No active profile, just quit
        return .terminateNow
    }
 
    // MARK: - Setup
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func setupSessionObservers() {
        // For logs or other custom handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired),
            name: NSNotification.Name(Constants.Notifications.sessionExpired),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionTimeUpdate(_:)),
            name: NSNotification.Name(Constants.Notifications.sessionTimeUpdated),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileConnected(_:)),
            name: NSNotification.Name(Constants.Notifications.profileConnected),
            object: nil
        )
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleSessionExpired() {
    }
    
    @objc private func handleSessionTimeUpdate(_ notification: Notification) {
        // Handled by MenuBarManager's live update callback
    }
    
    @objc private func handleProfileConnected(_ notification: Notification) {
        if let profile = notification.userInfo?[Constants.NotificationKeys.profile] as? SSOProfile {
        }
    }
    
    // MARK: - Helpers
    
    private func showAlert(_ title: String, info: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let actionIdentifier = response.actionIdentifier

        switch actionIdentifier {
        case "refresh-action":
            // User tapped refresh button
            DispatchQueue.main.async {
                MenuBarManager.shared.refreshCurrentSession()
            }

        case "ignore-action", "remind-later-action":
            // User chose to ignore or be reminded later - do nothing
            break

        default:
            // Default action (notification tapped but no button)
            break
        }

        completionHandler()
    }

    // Allow notifications to show even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
