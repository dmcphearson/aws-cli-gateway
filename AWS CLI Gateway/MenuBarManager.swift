import SwiftUI
import Cocoa
import CommonCrypto
import UserNotifications

// MARK: - Floating Panel (replaces NSMenu for full interactivity)

class StatusBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onClose: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override func resignKey() {
        super.resignKey()
        close()
        onClose?()
    }
}

// MARK: - SwiftUI Content View

struct StatusBarContentView: View {
    @ObservedObject var viewModel: StatusBarViewModel
    @State private var showDisconnected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("AWS Profiles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Connected profiles
            ForEach(viewModel.connectedProfiles, id: \.name) { profile in
                ConnectedProfileRow(
                    profile: profile,
                    onRefresh: { viewModel.refreshProfile(profile.name) },
                    onDisconnect: { viewModel.disconnectProfile(profile.name) }
                )
            }

            // Disconnected profiles toggle
            if !viewModel.disconnectedProfiles.isEmpty {
                Divider().padding(.horizontal, 10).padding(.vertical, 4)

                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showDisconnected.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showDisconnected ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                        Text("\(viewModel.disconnectedProfiles.count) more profile\(viewModel.disconnectedProfiles.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                if showDisconnected {
                    ForEach(viewModel.disconnectedProfiles, id: \.name) { profile in
                        DisconnectedProfileRow(
                            profile: profile,
                            onConnect: { viewModel.connectProfile(profile.name) }
                        )
                    }
                }
            }

            Divider().padding(.horizontal, 10).padding(.vertical, 4)

            // Actions
            if !viewModel.connectedProfiles.isEmpty {
                MenuActionButton(title: "Open AWS Console", icon: "globe") {
                    viewModel.openConsole()
                }
                MenuActionButton(title: "Disconnect All", icon: "xmark.circle") {
                    viewModel.disconnectAll()
                }
                Divider().padding(.horizontal, 10).padding(.vertical, 4)
            }

            MenuActionButton(title: "Settings...", icon: "gear") {
                viewModel.openSettings()
            }
            MenuActionButton(title: "Quit", icon: "power") {
                NSApp.terminate(nil)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 300)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ConnectedProfileRow: View {
    let profile: ProfileDisplayInfo
    let onRefresh: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(profile.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(profile.timeRemaining)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: onDisconnect) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch profile.status {
        case .active: return .green
        case .expiringSoon: return .orange
        case .expired: return .red
        default: return .gray
        }
    }
}

struct DisconnectedProfileRow: View {
    let profile: ProfileDisplayInfo
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.gray)
                .frame(width: 8, height: 8)

            Text(profile.name)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button(action: onConnect) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

struct MenuActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .padding(.horizontal, 4)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - View Model

struct ProfileDisplayInfo {
    let name: String
    var timeRemaining: String
    var status: ProfileSessionStatus
}

class StatusBarViewModel: ObservableObject {
    @Published var connectedProfiles: [ProfileDisplayInfo] = []
    @Published var disconnectedProfiles: [ProfileDisplayInfo] = []

    weak var manager: MenuBarManager?

    func refresh() {
        let connected = ProfileHistoryManager.shared.getConnectedProfiles()
        let connectedNames = Set(connected.map { $0.originalName })
        let allProfiles = ConfigManager.shared.getProfiles()

        connectedProfiles = connected.map { info in
            let session = SessionManager.shared.activeSessions[info.originalName]
            return ProfileDisplayInfo(
                name: info.originalName,
                timeRemaining: session?.formattedTimeRemaining ?? "--:--:--",
                status: session?.status ?? .connecting
            )
        }

        disconnectedProfiles = allProfiles
            .filter { !connectedNames.contains($0.name) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { ProfileDisplayInfo(name: $0.name, timeRemaining: "", status: .expired) }
    }

    func refreshProfile(_ name: String) {
        Task {
            let success = await SessionManager.shared.refreshSSOSession(for: name)
            if !success {
                await MainActor.run {
                    manager?.showError("Refresh Failed", message: "Could not refresh session for \(name). The refresh token may have expired — try connecting again.")
                }
            }
        }
    }

    func disconnectProfile(_ name: String) {
        Task {
            SessionManager.shared.cleanDisconnect(for: name)
            ProfileHistoryManager.shared.setProfileDisconnected(name)
            _ = try? await CommandRunner.shared.runCommand("aws", args: ["sso", "logout", "--profile", name])
            await MainActor.run {
                if manager?.activeProfile == name {
                    manager?.activeProfile = ProfileHistoryManager.shared.getConnectedProfileOriginalName()
                }
                refresh()
            }
        }
    }

    func connectProfile(_ name: String) {
        guard ProfileHistoryManager.shared.canConnectProfile() else {
            Task { @MainActor in
                manager?.showError("Connection Limit", message: "Maximum \(ProfileHistoryManager.maxConcurrentProfiles) concurrent profiles reached.")
            }
            return
        }
        manager?.connectProfileByName(name)
    }

    func disconnectAll() {
        manager?.disconnectAllProfiles()
    }

    func openConsole() {
        manager?.openConsole()
    }

    func openSettings() {
        manager?.openSettings()
    }
}

// MARK: - MenuBarManager

class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var panel: StatusBarPanel?
    private let viewModel = StatusBarViewModel()

    // Notification cooldown
    private var lastNotificationSent: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60

    fileprivate(set) var activeProfile: String? {
        didSet {
            Task { @MainActor in
                if let profile = activeProfile {
                    SessionManager.shared.startMonitoring(for: profile)
                    ProfileHistoryManager.shared.setConnectedProfile(profile)
                } else if ProfileHistoryManager.shared.getConnectedProfiles().isEmpty {
                    SessionManager.shared.cleanDisconnect()
                }
                viewModel.refresh()
            }
        }
    }

    private override init() {
        super.init()
        viewModel.manager = self
    }

    // MARK: - Setup

    func setup() {
        Task { @MainActor in
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem?.button {
                button.image = NSImage(named: "cloud-lock")
                button.image?.isTemplate = true
                button.action = #selector(togglePanel)
                button.target = self
            }

            // No NSMenu — we use a panel instead
            statusItem?.menu = nil

            setupNotifications()
            restoreActiveSessions()
            viewModel.refresh()

            // Live session updates
            SessionManager.shared.onSessionsUpdated = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.viewModel.refresh()
                }
            }

            SessionManager.shared.onTokenExpirationWarning = { [weak self] profileName, timeUntilExpiry in
                DispatchQueue.main.async {
                    self?.handleTokenExpirationWarning(profileName: profileName, timeUntilExpiry: timeUntilExpiry)
                }
            }
        }
    }

    @objc private func togglePanel() {
        if let panel = panel, panel.isVisible {
            panel.close()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Clean up any stale panel
        panel?.close()
        panel = nil

        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        viewModel.refresh()

        let contentView = StatusBarContentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame.size = hostingView.fittingSize

        let panelRect = NSRect(x: 0, y: 0, width: hostingView.fittingSize.width, height: hostingView.fittingSize.height)
        let newPanel = StatusBarPanel(contentRect: panelRect)
        newPanel.contentView = hostingView
        newPanel.onClose = { [weak self] in
            self?.panel = nil
        }

        // Position below the status bar item
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let panelX = screenRect.midX - panelRect.width / 2
        let panelY = screenRect.minY - panelRect.height - 4
        newPanel.setFrameOrigin(NSPoint(x: panelX, y: panelY))

        newPanel.makeKeyAndOrderFront(nil)
        self.panel = newPanel
    }

    // MARK: - Session Restore

    @MainActor
    private func restoreActiveSessions() {
        ProfileHistoryManager.shared.clearConnectedProfile()

        let allProfiles = ConfigManager.shared.getProfiles()
        var restoredCount = 0

        for profile in allProfiles {
            guard restoredCount < ProfileHistoryManager.maxConcurrentProfiles else { break }

            let profileName = profile.name
            var hasValidSession = false

            if let ssoExpiry = SSOTokenManager.shared.getSSOTokenExpiry(forProfile: profileName),
               ssoExpiry > Date() {
                hasValidSession = true
            }

            if !hasValidSession,
               let sessionName = ConfigManager.shared.getSSOSessionName(for: profileName) {
                let homeDir = FileManager.default.homeDirectoryForCurrentUser
                let ssoCachePath = homeDir.appendingPathComponent(".aws/sso/cache")
                let data = Data(sessionName.utf8)
                var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
                let hash = digest.map { String(format: "%02hhx", $0) }.joined()

                let tokenFile = ssoCachePath.appendingPathComponent("\(hash).json")
                if let fileData = try? Data(contentsOf: tokenFile),
                   let json = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any],
                   json["refreshToken"] != nil {
                    hasValidSession = true
                }
            }

            if hasValidSession {
                ProfileHistoryManager.shared.setConnectedProfile(profileName)
                if activeProfile == nil { activeProfile = profileName }
                SessionManager.shared.startMonitoring(for: profileName)
                restoredCount += 1
            }
        }
    }

    func hasActiveSession() -> Bool {
        return activeProfile != nil
    }

    func cleanup() {
        NotificationCenter.default.removeObserver(self)
        panel?.close()
        statusItem = nil
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfilesUpdated),
            name: Notification.Name(Constants.Notifications.profilesUpdated),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileConnected(_:)),
            name: Notification.Name(Constants.Notifications.profileConnected),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionExpired(_:)),
            name: Notification.Name(Constants.Notifications.sessionExpired),
            object: nil
        )
    }

    // MARK: - Actions (called by ViewModel)

    func connectProfileByName(_ name: String) {
        let profiles = ConfigManager.shared.getProfiles()
        guard let profile = profiles.first(where: { $0.name == name }) else { return }

        Task {
            do {
                if let iamProfile = profile as? IAMProfile {
                    let sourceProfileName = iamProfile.sourceProfile
                    let allProfiles = ConfigManager.shared.getProfiles()
                    if let sourceProfile = allProfiles.first(where: { $0.name == sourceProfileName }) as? SSOProfile {
                        _ = try await CommandRunner.shared.runCommand("aws", args: ["sso", "login", "--profile", sourceProfile.name])
                    }
                } else if profile is SSOProfile {
                    _ = try await CommandRunner.shared.runCommand("aws", args: ["sso", "login", "--profile", profile.name])
                }

                _ = try await CommandRunner.shared.runCommand("aws", args: ["sts", "get-caller-identity", "--profile", profile.name])
                try await Task.sleep(nanoseconds: 200_000_000)

                await MainActor.run {
                    self.activeProfile = profile.name
                    ProfileHistoryManager.shared.setConnectedProfile(profile.name)
                    self.viewModel.refresh()
                }

                NotificationCenter.default.post(
                    name: Notification.Name(Constants.Notifications.profileConnected),
                    object: nil,
                    userInfo: [Constants.NotificationKeys.profile: profile]
                )
            } catch {
                await MainActor.run {
                    self.showError("Login Failed", message: error.localizedDescription)
                }
            }
        }
    }

    func disconnectAllProfiles() {
        guard let profile = activeProfile else { return }
        Task {
            SessionManager.shared.cleanDisconnect()
            _ = try? await CommandRunner.shared.runCommand("aws", args: ["sso", "logout", "--profile", profile])
            ProfileHistoryManager.shared.clearConnectedProfile()
            await MainActor.run {
                self.activeProfile = nil
                self.viewModel.refresh()
            }
        }
    }

    func openConsole() {
        guard let activeProfile = activeProfile else { return }
        if let ssoStartUrl = ConfigManager.shared.getSSOStartUrl(for: activeProfile),
           let url = URL(string: ssoStartUrl) {
            NSWorkspace.shared.open(url)
        }
    }

    func openSettings() {
        panel?.close()
        WindowManager.shared.showSettingsWindow()
    }

    func refreshCurrentSession() {
        guard let activeProfile = self.activeProfile else { return }
        Task {
            let success = await SessionManager.shared.refreshSSOSession(for: activeProfile)
            if !success {
                await MainActor.run {
                    showError("Session Refresh Failed",
                             message: "Unable to refresh your SSO session automatically. Please run 'aws sso login --profile \(activeProfile)' in Terminal.")
                }
            }
        }
    }

    // MARK: - Notification Handlers

    @MainActor
    @objc private func handleProfilesUpdated() {
        viewModel.refresh()
    }

    @MainActor
    @objc private func handleProfileConnected(_ notification: Notification) {
        if let profile = notification.userInfo?[Constants.NotificationKeys.profile] as? AWSProfile {
            activeProfile = profile.name
            ProfileHistoryManager.shared.setConnectedProfile(profile.name)
        }
    }

    @MainActor
    @objc private func handleSessionExpired(_ notification: Notification) {
        if let profileName = notification.userInfo?[Constants.NotificationKeys.profileName] as? String {
            ProfileHistoryManager.shared.setProfileDisconnected(profileName)
            if activeProfile == profileName {
                activeProfile = ProfileHistoryManager.shared.getConnectedProfileOriginalName()
            }
        } else {
            ProfileHistoryManager.shared.clearConnectedProfile()
            activeProfile = nil
        }
        viewModel.refresh()
    }

    // MARK: - Token Expiration Handling

    private func handleTokenExpirationWarning(profileName: String, timeUntilExpiry: TimeInterval) {
        let level: String
        if timeUntilExpiry <= 0 {
            level = "expired"
        } else if timeUntilExpiry <= 60 {
            level = "critical"
        } else if timeUntilExpiry <= 300 {
            level = "warning"
        } else {
            return
        }

        let key = "\(profileName)-\(level)"
        if let lastSent = lastNotificationSent[key],
           Date().timeIntervalSince(lastSent) < notificationCooldown {
            return
        }
        lastNotificationSent[key] = Date()

        switch level {
        case "expired":
            showTokenExpiredNotification(profileName: profileName)
        case "critical":
            showTokenExpiringNotification(profileName: profileName, timeUntilExpiry: timeUntilExpiry, isCritical: true)
        case "warning":
            showTokenExpiringNotification(profileName: profileName, timeUntilExpiry: timeUntilExpiry, isCritical: false)
        default:
            break
        }
    }

    private func showTokenExpiredNotification(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "AWS CLI Gateway"
        content.body = "Your AWS SSO session for '\(profileName)' has expired. Please refresh to continue."
        content.sound = .default

        let refreshAction = UNNotificationAction(identifier: "refresh-action", title: "Refresh Session", options: [.foreground])
        let ignoreAction = UNNotificationAction(identifier: "ignore-action", title: "Ignore", options: [])
        let category = UNNotificationCategory(identifier: "token-expired", actions: [refreshAction, ignoreAction], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "token-expired"
        content.userInfo = ["profileName": profileName]

        let request = UNNotificationRequest(identifier: "token-expired-\(profileName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func showTokenExpiringNotification(profileName: String, timeUntilExpiry: TimeInterval, isCritical: Bool) {
        let minutes = Int(timeUntilExpiry / 60)
        let seconds = Int(timeUntilExpiry.truncatingRemainder(dividingBy: 60))

        let content = UNMutableNotificationContent()
        content.title = "AWS CLI Gateway"

        if isCritical {
            content.body = "Your AWS SSO session for '\(profileName)' expires in \(seconds) seconds!"
            content.sound = .defaultCritical
        } else {
            let timeText = minutes > 0 ? "\(minutes) minute\(minutes == 1 ? "" : "s")" : "\(seconds) seconds"
            content.body = "Your AWS SSO session for '\(profileName)' expires in \(timeText)."
            content.sound = .default
        }

        let refreshAction = UNNotificationAction(identifier: "refresh-action", title: "Refresh Now", options: [.foreground])
        let remindLaterAction = UNNotificationAction(identifier: "remind-later-action", title: "Remind Later", options: [])
        let category = UNNotificationCategory(identifier: "token-expiring", actions: [refreshAction, remindLaterAction], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "token-expiring"
        content.userInfo = ["profileName": profileName]

        let request = UNNotificationRequest(identifier: "token-expiring-\(profileName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Helpers

    @MainActor
    func showError(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
