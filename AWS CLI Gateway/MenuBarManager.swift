import SwiftUI
import Cocoa
import UserNotifications


class HighlightableMenuItemView: NSView {
    private let backgroundLayer = CALayer()
    private var highlightObserver: NSKeyValueObservation?
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    func refreshTracking() {
        print("🔍 DIAG: refreshTracking called for \(enclosingMenuItem?.title ?? "unknown item")")
        // Remove existing tracking area
        if let existing = trackingArea {
            print("🔍 DIAG: Removing existing tracking area")
            removeTrackingArea(existing)
        } else {
            print("🔍 DIAG: No existing tracking area found")
        }
        
        // Create and add a new tracking area
        print("🔍 DIAG: New tracking area added")
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        
        if let area = trackingArea {
            addTrackingArea(area)
        }
        
        // Ensure we're observing the menu item
        if let menuItem = enclosingMenuItem {
            print("🔍 DIAG: Highlight observer is \(highlightObserver == nil ? "nil" : "not nil")")
            // Ensure highlight observer is set up
            if highlightObserver == nil {
                print("🔍 DIAG: Highlight observer \(highlightObserver == nil ? "not" : "") created")
                highlightObserver = menuItem.observe(\.isHighlighted, options: [.new]) { [weak self] menuItem, _ in
                    guard let self = self else { return }
                    
                    if menuItem.isHighlighted {
                        self.backgroundLayer.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
                    } else {
                        self.backgroundLayer.backgroundColor = NSColor.clear.cgColor
                    }
                }
            }
        }
    }
    
    // In HighlightableMenuItemView class, outside any methods
    func updateHighlightState() {
        // Update the view based on its menu item's highlight state
        if let menuItem = enclosingMenuItem {
            updateBackgroundColor(isHighlighted: menuItem.isHighlighted)
        }
    }
    
    private func updateBackgroundColor(isHighlighted: Bool) {
        // Your existing highlighting code
        if isHighlighted {
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func setupView() {
        wantsLayer = true

        backgroundLayer.frame = bounds
        backgroundLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundLayer.backgroundColor = NSColor.clear.cgColor

        // Add rounded corners to match macOS 15 style
        backgroundLayer.cornerRadius = 6
        backgroundLayer.masksToBounds = true

        // Create horizontal-only insets
        let horizontalInset: CGFloat = 4
        let originalFrame = bounds

        // Create a new frame with horizontal insets only
        let insetFrame = CGRect(
            x: originalFrame.origin.x + horizontalInset,
            y: originalFrame.origin.y,
            width: originalFrame.width - (horizontalInset * 2),
            height: originalFrame.height
        )

        backgroundLayer.frame = insetFrame

        if let hostLayer = layer {
            hostLayer.insertSublayer(backgroundLayer, at: 0)
        }

        // Add tracking area to handle mouse events directly
        setupTrackingArea()
    }


    private func setupTrackingArea() {
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        trackingArea = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInActiveApp],
                                      owner: self,
                                      userInfo: nil)

        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        print("🔍 DIAG: mouseEntered for \(enclosingMenuItem?.title ?? "unknown item")")
        super.mouseEntered(with: event)
        setHighlighted(true)
    }

    override func mouseExited(with event: NSEvent) {
        print("🔍 DIAG: mouseExited for \(enclosingMenuItem?.title ?? "unknown item")")
        super.mouseExited(with: event)
        setHighlighted(false)
    }

    func setHighlighted(_ highlighted: Bool) {
        // Use layer's draw immediately functionality
        if highlighted {
            backgroundLayer.actions = [
                "backgroundColor": NSNull()
            ]
            backgroundLayer.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        } else {
            backgroundLayer.actions = [
                "backgroundColor": NSNull()
            ]
            backgroundLayer.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func viewDidMoveToWindow() {
        print("🔍 DIAG: viewDidMoveToWindow for \(enclosingMenuItem?.title ?? "unknown item")")
        super.viewDidMoveToWindow()
    }

    override func viewDidMoveToSuperview() {
        print("🔍 DIAG: viewDidMoveToSuperview for \(enclosingMenuItem?.title ?? "unknown item")")
        super.viewDidMoveToSuperview()

        if let menuItem = enclosingMenuItem {
            menuItem.isEnabled = true

            highlightObserver = menuItem.observe(\.isHighlighted, options: [.new]) { [weak self] menuItem, _ in
                guard let self = self else { return }

                self.setHighlighted(menuItem.isHighlighted)
            }
        }
    }

    deinit {
        highlightObserver?.invalidate()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
    }
}

class ProfileButton: NSButton {
    var profile: AWSProfile?
}

class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()

    // MARK: - Menubar & Menu
    private var statusItem: NSStatusItem?
    private var mainMenu: NSMenu!
    private var highlightTimer: Timer?

    // Menu items
    private var connectionsMenuItem: NSMenuItem!
    private var sessionMenuItem: NSMenuItem!
    private var renewMenuItem: NSMenuItem!
    private var disconnectMenuItem: NSMenuItem!

    // The primary active profile (for backward compat with single-profile flows)
    private var activeProfile: String? {
        didSet {
            Task { @MainActor in
                if let profile = activeProfile {
                    SessionManager.shared.startMonitoring(for: profile)
                    ProfileHistoryManager.shared.setConnectedProfile(profile)
                } else if ProfileHistoryManager.shared.getConnectedProfiles().isEmpty {
                    SessionManager.shared.cleanDisconnect()
                }
                buildMenu()
            }
        }
    }

    // Per-profile text fields for live countdown updates (avoid full menu rebuild every second)
    private var sessionTimeFields: [String: NSTextField] = [:]

    // Notification cooldown: tracks last notification time per profile+threshold to prevent duplicates
    private var lastNotificationSent: [String: Date] = [:]
    private let notificationCooldown: TimeInterval = 60

    private override init() {}
    
    func menuWillOpen(_ menu: NSMenu) {
        print("🔍 DIAG: menuWillOpen called for \(menu == mainMenu ? "main menu" : "submenu")")
        // This will be called whenever the menu is about to be displayed
        if menu == mainMenu || menu == connectionsMenuItem?.submenu {
            // Reinitialize tracking for all custom views
            reinitializeMenuItemViews(in: menu)
        }
        highlightTimer?.invalidate() // Safety cleanup
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateHighlightsBasedOnMousePosition()
        }

        // Add the timer to the main run loop to ensure it works in menu context
        if let timer = highlightTimer {
            RunLoop.main.add(timer, forMode: .eventTracking)
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        // Stop the timer when menu closes
        highlightTimer?.invalidate()
        highlightTimer = nil
    }
    
    
    private func updateHighlightsBasedOnMousePosition() {
        guard let menu = statusItem?.menu else { return }
        let mouseLocation = NSEvent.mouseLocation

        // Reset all highlights first (optional)
        resetAllHighlights(in: menu)

        // Process menu items for highlighting
        processMenuItemsForHighlighting(in: menu, mouseLocation: mouseLocation)
    }

    private func resetAllHighlights(in menu: NSMenu) {
        for item in menu.items {
            if let view = item.view as? HighlightableMenuItemView {
                view.setHighlighted(false) // Use existing method instead
            }

            if let submenu = item.submenu {
                resetAllHighlights(in: submenu)
            }
        }
    }
    
    private func processMenuItemsForHighlighting(in menu: NSMenu, mouseLocation: NSPoint) {
        for item in menu.items {
            if let view = item.view as? HighlightableMenuItemView {
                // Convert view's frame to screen coordinates
                if let window = view.window {
                    let frameInWindow = view.convert(view.bounds, to: nil)
                    let frameInScreen = window.convertToScreen(frameInWindow)

                    let shouldHighlight = frameInScreen.contains(mouseLocation)

                    // Directly update the view instead of changing isHighlighted
                    view.setHighlighted(shouldHighlight)
                }
            }

            // Process submenu if it has items
            if let submenu = item.submenu, submenu.numberOfItems > 0 {
                processMenuItemsForHighlighting(in: submenu, mouseLocation: mouseLocation)
            }
        }
    }

    private func reinitializeMenuItemViews(in menu: NSMenu) {
        print("🔍 DIAG: Reinitializing \(menu.items.count) menu items")
        for menuItem in menu.items {
            // Process this item's view if it's a HighlightableMenuItemView
            if let itemView = menuItem.view as? HighlightableMenuItemView {
                // Tell the view to refresh its tracking areas and highlight state
                itemView.refreshTracking()
            }

            // Recursively process submenu items
            if let submenu = menuItem.submenu {
                reinitializeMenuItemViews(in: submenu)
            }
        }
    }
    
    // MARK: - Setup

    func setup() {
        Task { @MainActor in
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            
            if let button = statusItem?.button {
                button.image = NSImage(named: "cloud-lock")
                button.image?.isTemplate = true
            }
            
            mainMenu = NSMenu()
            mainMenu.delegate = self
            statusItem?.menu = mainMenu
            
            setupNotifications()
            
            buildMenu()
            
            SessionManager.shared.onSessionUpdate = { [weak self] timeString in
                DispatchQueue.main.async {
                    if let container = self?.sessionMenuItem?.view,
                       let textField = container.subviews.first as? NSTextField {
                        textField.stringValue = timeString
                    }
                }
            }

            // Handle token expiration warnings
            SessionManager.shared.onTokenExpirationWarning = { [weak self] profileName, timeUntilExpiry in
                DispatchQueue.main.async {
                    self?.handleTokenExpirationWarning(profileName: profileName, timeUntilExpiry: timeUntilExpiry)
                }
            }
        }
    }

    func cleanup() {
        NotificationCenter.default.removeObserver(self)
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

    // MARK: - Build the Dropdown

    @MainActor
    @objc private func buildMenu() {
        let currentSessionTime = sessionMenuItem?.title ?? "Session: --:--:--"
        mainMenu.removeAllItems()

        let connectedProfiles = ProfileHistoryManager.shared.getConnectedProfiles()
        let connectionsSubMenu = NSMenu()
        var profiles = ConfigManager.shared.getProfiles()

        profiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        // Calculate the maximum width needed for the profile names
        var maxProfileWidth: CGFloat = 50 // Minimum width

        // Get widths for all profile names
        for profile in profiles {
            let nameWidth = calculateTextWidth(profile.displayName, withFont: NSFont.systemFont(ofSize: NSFont.systemFontSize))
            maxProfileWidth = max(maxProfileWidth, nameWidth)
        }

        // Always show star buttons for connect/disconnect toggle
        let hasActiveSession = !connectedProfiles.isEmpty || activeProfile != nil
        let starWidth: CGFloat = 30
        let leftPadding: CGFloat = 0
        let deleteWidth: CGFloat = 25
        let rightPadding: CGFloat = 25
        let totalItemWidth = leftPadding + starWidth + maxProfileWidth + deleteWidth + rightPadding

        if profiles.isEmpty {
            let noProfilesItem = NSMenuItem(title: "No Profiles Available", action: nil, keyEquivalent: "")
            connectionsSubMenu.addItem(noProfilesItem)
        } else {
            for profile in profiles {
                let itemView = HighlightableMenuItemView(frame: NSRect(x: 0, y: 0, width: totalItemWidth, height: Constants.UI.menuItemHeight))

                let profileButtonX: CGFloat = 35
                let deleteButtonX: CGFloat = totalItemWidth - 30

                // Star button — always visible, toggles connect/disconnect
                let starButton = ProfileButton(frame: NSRect(x: 5, y: 0, width: 25, height: Constants.UI.menuItemHeight))
                starButton.profile = profile
                starButton.target = self
                starButton.action = #selector(toggleProfileConnection(_:))
                starButton.bezelStyle = .inline
                starButton.isBordered = false

                let isProfileConnected = connectedProfiles.contains(where: { $0.originalName == profile.name })
                if isProfileConnected {
                    starButton.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Connected")
                    if let img = starButton.image {
                        starButton.image = tintImage(img, with: .systemYellow)
                    }
                } else {
                    starButton.image = NSImage(systemSymbolName: "star", accessibilityDescription: "Connect")
                    if let img = starButton.image {
                        starButton.image = tintImage(img, with: .secondaryLabelColor)
                    }
                }

                // Use the profile's displayName property which already handles the default case
                let profileButton = ProfileButton(frame: NSRect(x: profileButtonX, y: 0, width: maxProfileWidth, height: Constants.UI.menuItemHeight))
                profileButton.title = profile.displayName
                profileButton.target = self
                profileButton.action = #selector(showProfileDetails(_:))
                profileButton.bezelStyle = .inline
                profileButton.isBordered = false
                profileButton.setButtonType(.momentaryPushIn)
                profileButton.profile = profile
                profileButton.alignment = .left

                // Position delete button relative to total width
                let deleteButton = ProfileButton(frame: NSRect(x: deleteButtonX, y: 0, width: 25, height: Constants.UI.menuItemHeight))
                deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
                deleteButton.bezelStyle = .inline
                deleteButton.isBordered = false
                deleteButton.target = self
                deleteButton.action = #selector(deleteProfile(_:))
                deleteButton.profile = profile

                itemView.addSubview(starButton)
                itemView.addSubview(profileButton)
                itemView.addSubview(deleteButton)

                let menuItem = NSMenuItem()
                menuItem.view = itemView
                menuItem.isEnabled = true
                connectionsSubMenu.addItem(menuItem)
            }
        }

        // Use maximum of totalItemWidth or 250 for the menu width
        let menuWidth = max(totalItemWidth, 250)

        // Active Sessions section
        if !connectedProfiles.isEmpty {
            mainMenu.addItem(NSMenuItem.separator())

            // Header
            let headerItem = NSMenuItem(title: "Active Sessions (\(connectedProfiles.count)/\(ProfileHistoryManager.maxConcurrentProfiles))", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            mainMenu.addItem(headerItem)

            // Clear old text field references
            sessionTimeFields.removeAll()

            // Per-profile session rows
            for profileInfo in connectedProfiles {
                let profileName = profileInfo.originalName
                let session = SessionManager.shared.activeSessions[profileName]
                let timeString = session?.formattedTimeRemaining ?? "--:--:--"
                let rowHeight: CGFloat = 28
                let rowWidth = menuWidth

                let rowView = HighlightableMenuItemView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight))

                // Status dot
                let dotSize: CGFloat = 8
                let dotView = NSView(frame: NSRect(x: 10, y: (rowHeight - dotSize) / 2, width: dotSize, height: dotSize))
                dotView.wantsLayer = true
                dotView.layer?.cornerRadius = dotSize / 2
                switch session?.status {
                case .active: dotView.layer?.backgroundColor = NSColor.systemGreen.cgColor
                case .expiringSoon: dotView.layer?.backgroundColor = NSColor.systemOrange.cgColor
                case .expired: dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
                default: dotView.layer?.backgroundColor = NSColor.systemGray.cgColor
                }
                rowView.addSubview(dotView)

                // Profile name
                let nameField = NSTextField(frame: NSRect(x: 24, y: 0, width: maxProfileWidth, height: rowHeight))
                nameField.stringValue = profileName
                nameField.isEditable = false
                nameField.isBordered = false
                nameField.backgroundColor = .clear
                nameField.textColor = .labelColor
                nameField.font = NSFont.systemFont(ofSize: 12)
                nameField.lineBreakMode = .byTruncatingTail
                rowView.addSubview(nameField)

                // Countdown
                let timerX = 24 + maxProfileWidth + 5
                let timerWidth: CGFloat = 65
                let timerField = NSTextField(frame: NSRect(x: timerX, y: 0, width: timerWidth, height: rowHeight))
                timerField.stringValue = timeString
                timerField.isEditable = false
                timerField.isBordered = false
                timerField.backgroundColor = .clear
                timerField.textColor = .secondaryLabelColor
                timerField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
                timerField.alignment = .right
                rowView.addSubview(timerField)
                sessionTimeFields[profileName] = timerField

                // Refresh button
                let refreshX = timerX + timerWidth + 4
                let refreshButton = ProfileButton(frame: NSRect(x: refreshX, y: 2, width: 22, height: rowHeight - 4))
                refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
                refreshButton.bezelStyle = .inline
                refreshButton.isBordered = false
                refreshButton.target = self
                refreshButton.action = #selector(refreshProfileSession(_:))
                refreshButton.profile = profiles.first(where: { $0.name == profileName })
                rowView.addSubview(refreshButton)

                // Disconnect button
                let disconnectX = refreshX + 24
                let disconnectButton = ProfileButton(frame: NSRect(x: disconnectX, y: 2, width: 22, height: rowHeight - 4))
                disconnectButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Disconnect")
                disconnectButton.bezelStyle = .inline
                disconnectButton.isBordered = false
                disconnectButton.target = self
                disconnectButton.action = #selector(disconnectSingleProfile(_:))
                disconnectButton.profile = profiles.first(where: { $0.name == profileName })
                rowView.addSubview(disconnectButton)

                let menuItem = NSMenuItem()
                menuItem.view = rowView
                mainMenu.addItem(menuItem)
            }

            // Set up the multi-session update callback (updates text fields without rebuilding menu)
            SessionManager.shared.onSessionsUpdated = { [weak self] sessions in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    for (profileName, session) in sessions {
                        self.sessionTimeFields[profileName]?.stringValue = session.formattedTimeRemaining
                    }
                }
            }

            // Also keep legacy single-profile callback for the primary profile
            SessionManager.shared.onSessionUpdate = { [weak self] timeString in
                DispatchQueue.main.async {
                    guard let self = self, let primary = self.activeProfile else { return }
                    self.sessionTimeFields[primary]?.stringValue = timeString.replacingOccurrences(of: "Session: ", with: "")
                }
            }

            mainMenu.addItem(NSMenuItem.separator())

            renewMenuItem = NSMenuItem(title: "Renew All Sessions", action: #selector(renewSession), keyEquivalent: "")
            renewMenuItem.target = self
            mainMenu.addItem(renewMenuItem)

            disconnectMenuItem = NSMenuItem(title: "Disconnect All", action: #selector(disconnectProfile), keyEquivalent: "")
            disconnectMenuItem.target = self
            mainMenu.addItem(disconnectMenuItem)

            mainMenu.addItem(NSMenuItem.separator())
        }
        
        connectionsMenuItem = NSMenuItem(title: "Connections", action: nil, keyEquivalent: "")
        connectionsMenuItem.submenu = connectionsSubMenu
        mainMenu.addItem(connectionsMenuItem)
        
        mainMenu.addItem(NSMenuItem.separator())

        let addProfileItem = NSMenuItem(title: "Add Profile...", action: #selector(showAddProfile), keyEquivalent: "n")
        addProfileItem.target = self
        mainMenu.addItem(addProfileItem)

        let clearCacheItem = NSMenuItem(title: "Clear Cache", action: #selector(clearCache), keyEquivalent: "")
        clearCacheItem.target = self
        mainMenu.addItem(clearCacheItem)

        let toolsSubmenu = NSMenu()
        let toolsItem = NSMenuItem(title: "Tools & Settings", action: nil, keyEquivalent: "")
        toolsItem.submenu = toolsSubmenu

        let installCLIItem = NSMenuItem(title: "Install CLI Tools", action: #selector(installCLI), keyEquivalent: "")
        installCLIItem.target = self
        toolsSubmenu.addItem(installCLIItem)

        if activeProfile != nil {
            let openConsoleItem = NSMenuItem(title: "Open AWS Console", action: #selector(openConsole), keyEquivalent: "")
            openConsoleItem.target = self
            toolsSubmenu.addItem(openConsoleItem)
        }

        toolsSubmenu.addItem(NSMenuItem.separator())

        let profileBindingsItem = NSMenuItem(title: "App Profile Bindings...", action: #selector(showAppProfileBindings), keyEquivalent: "")
        profileBindingsItem.target = self
        toolsSubmenu.addItem(profileBindingsItem)

        mainMenu.addItem(toolsItem)

        mainMenu.addItem(NSMenuItem.separator())
        mainMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func hasActiveSession() -> Bool {
        return activeProfile != nil
    }

    
    @objc func openConsole() {
        guard let activeProfile = activeProfile else {
            print("No active profile found")
            return
        }

        print("Opening console for profile: \(activeProfile)")

        // Get the SSO start URL from the config file
        if let ssoStartUrl = ConfigManager.shared.getSSOStartUrl(for: activeProfile) {
            print("Attempting to open URL: \(ssoStartUrl)")
            if let url = URL(string: ssoStartUrl) {
                let success = NSWorkspace.shared.open(url)
                print("URL open result: \(success ? "success" : "failed")")
            } else {
                print("Failed to create URL from string: \(ssoStartUrl)")
            }
        } else {
            print("No SSO start URL found for profile: \(activeProfile)")
        }
    }

    @MainActor
    @objc private func toggleProfileConnection(_ sender: ProfileButton) {
        guard let profile = sender.profile else { return }

        let connectedProfiles = ProfileHistoryManager.shared.getConnectedProfiles()
        let isConnected = connectedProfiles.contains(where: { $0.originalName == profile.name })

        if isConnected {
            // Disconnect this profile
            SessionManager.shared.stopMonitoring(for: profile.name)
            ProfileHistoryManager.shared.setProfileDisconnected(profile.name)
            if activeProfile == profile.name {
                activeProfile = ProfileHistoryManager.shared.getConnectedProfileOriginalName()
            }
            buildMenu()
        } else {
            // Connect this profile (additive)
            if !ProfileHistoryManager.shared.canConnectProfile() {
                showError("Connection Limit", message: "Maximum \(ProfileHistoryManager.maxConcurrentProfiles) concurrent profiles reached.")
                return
            }
            connectToProfile(sender)
        }
    }

    @MainActor
    @objc private func refreshProfileSession(_ sender: ProfileButton) {
        guard let profile = sender.profile else { return }
        Task {
            let success = await SessionManager.shared.refreshSSOSession(for: profile.name)
            if !success {
                showError("Refresh Failed", message: "Could not refresh session for \(profile.name)")
            }
        }
    }

    @MainActor
    @objc private func disconnectSingleProfile(_ sender: ProfileButton) {
        guard let profile = sender.profile else { return }
        Task {
            SessionManager.shared.cleanDisconnect(for: profile.name)
            ProfileHistoryManager.shared.setProfileDisconnected(profile.name)
            do {
                _ = try await CommandRunner.shared.runCommand("aws", args: ["sso", "logout", "--profile", profile.name])
            } catch {
                print("Logout failed for \(profile.name): \(error.localizedDescription)")
            }
            if activeProfile == profile.name {
                activeProfile = ProfileHistoryManager.shared.getConnectedProfileOriginalName()
            }
            buildMenu()
        }
    }

    @MainActor
    @objc private func showProfileDetails(_ sender: ProfileButton) {
        connectToProfile(sender)
    }

    // Helper method to tint NSImage
    private func tintImage(_ image: NSImage, with color: NSColor) -> NSImage {
        let tintedImage = image.copy() as! NSImage
        tintedImage.lockFocus()

        color.set()

        let imageRect = NSRect(origin: .zero, size: tintedImage.size)
        imageRect.fill(using: .sourceAtop)

        tintedImage.unlockFocus()
        return tintedImage
    }

    // MARK: - Actions

    @MainActor
    @objc private func connectToProfile(_ sender: ProfileButton) {
        guard let profile = sender.profile else { return }

        Task {
            do {
                // Check if this is an IAM profile that needs SSO login first
                if let iamProfile = profile as? IAMProfile {
                    // First check if we need to login to the source profile
                    let sourceProfileName = iamProfile.sourceProfile
                    let _ = iamProfile.ssoSession

                    // Get the source profile
                    let profiles = ConfigManager.shared.getProfiles()
                    if let sourceProfile = profiles.first(where: { $0.name == sourceProfileName }) as? SSOProfile {
                        // Try to login to the source profile first
                        _ = try await CommandRunner.shared.runCommand("aws", args: [
                            "sso", "login", "--profile", sourceProfile.name
                        ])
                    }
                } else if profile is SSOProfile {
                    // For regular SSO profiles, just login directly
                    _ = try await CommandRunner.shared.runCommand("aws", args: [
                        "sso", "login", "--profile", profile.name
                    ])
                }

                // Now verify the profile works by getting caller identity
                _ = try await CommandRunner.shared.runCommand("aws", args: [
                    "sts", "get-caller-identity", "--profile", profile.name
                ])

                try await Task.sleep(nanoseconds: 200_000_000)

                // Set this profile as the active profile
                activeProfile = profile.name

                // Also mark it as connected in the ProfileHistoryManager
                if let profileId = ProfileHistoryManager.shared.getIdForProfile(profile.name) {
                    ProfileHistoryManager.shared.setConnectedProfileById(profileId)
                } else {
                    // If we don't have an ID yet, set it by name
                    ProfileHistoryManager.shared.setConnectedProfile(profile.name)
                }

                NotificationCenter.default.post(
                    name: Notification.Name(Constants.Notifications.profileConnected),
                    object: nil,
                    userInfo: [Constants.NotificationKeys.profile: profile]
                )

                // Rebuild menu to show star buttons now that there's an active session
                buildMenu()

            } catch {
                showError("Login Failed", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    @objc private func deleteProfile(_ sender: ProfileButton) {
        guard let profile = sender.profile else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Profile"
        alert.informativeText = "Are you sure you want to delete the profile '\(profile.displayName)'? This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if profile.name == activeProfile {
                // If the active profile is being deleted, disconnect first
                Task {
                    do {
                        SessionManager.shared.cleanDisconnect()
                        // Attempt to properly logout via AWS CLI
                        _ = try await CommandRunner.shared.runCommand("aws", args: [
                            "sso", "logout", "--profile", profile.name])
                    } catch {
                        // If logout fails, still continue with deletion
                        print("Logout failed during profile deletion: \(error.localizedDescription)")
                    }

                    // Clear the connected profile status
                    ProfileHistoryManager.shared.clearConnectedProfile()

                    ConfigManager.shared.clearCache()
                    self.activeProfile = nil
                }
            }

            ConfigManager.shared.deleteProfile(profile.name)
            buildMenu()

            NotificationCenter.default.post(
                name: Notification.Name(Constants.Notifications.profilesUpdated),
                object: nil
            )
        }
    }

    @MainActor
    @objc private func renewSession() {
        Task {
            do {
                try await SessionManager.shared.renewSession()
            } catch {
                showError("Session Renewal Failed", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    @objc private func disconnectProfile() {
        guard let profile = activeProfile else { return }
        Task {
            do {
                SessionManager.shared.cleanDisconnect()
                _ = try await CommandRunner.shared.runCommand("aws", args: [
                    "sso", "logout", "--profile", profile])

                // Clear the connected profile
                ProfileHistoryManager.shared.clearConnectedProfile()

                ConfigManager.shared.clearCache()
                self.activeProfile = nil
            } catch {
                ConfigManager.shared.clearCache()
                SessionManager.shared.cleanDisconnect()

                // Still clear the connected profile even if logout fails
                ProfileHistoryManager.shared.clearConnectedProfile()

                self.activeProfile = nil
                await MainActor.run {
                    showError("Logout Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    @objc private func showAddProfile() {
        WindowManager.shared.showAddProfileWindow()
    }

    @MainActor
    @objc private func clearCache() {
        do {
            let message = try ScriptManager.shared.clearAWSCache()

            // Show success feedback
            let alert = NSAlert()
            alert.messageText = "Cache Cleared"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            // Show error feedback
            let alert = NSAlert()
            alert.messageText = "Operation Failed"
            alert.informativeText = "Failed to clear cache: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @MainActor
    @objc private func showAppProfileBindings() {
        let bindings = AppProfileBindingManager.shared.getBindings()
        let profiles = ConfigManager.shared.getProfiles()

        let alert = NSAlert()
        alert.messageText = "App Profile Bindings"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add Binding")
        alert.addButton(withTitle: "Install Shell Script")
        alert.addButton(withTitle: "Close")

        if bindings.isEmpty {
            alert.informativeText = "No bindings configured.\n\nBindings let you assign specific AWS profiles to commands (e.g., 'claude' → ClaudeCode) so you don't need shell wrappers or exported AWS_PROFILE."
        } else {
            let bindingList = bindings.map { "  \($0.command) → \($0.profileName)" }.joined(separator: "\n")
            alert.informativeText = "Current bindings:\n\(bindingList)\n\nBindings auto-set AWS_PROFILE per command."
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Add binding
            let addAlert = NSAlert()
            addAlert.messageText = "Add App Profile Binding"
            addAlert.informativeText = "Command name (e.g., 'claude', 'terraform'):"
            addAlert.addButton(withTitle: "Add")
            addAlert.addButton(withTitle: "Cancel")

            let commandField = NSTextField(frame: NSRect(x: 0, y: 32, width: 250, height: 24))
            commandField.placeholderString = "command name"

            let profilePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
            for profile in profiles {
                profilePopup.addItem(withTitle: profile.name)
            }

            let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 60))
            accessoryView.addSubview(commandField)
            accessoryView.addSubview(profilePopup)
            addAlert.accessoryView = accessoryView

            if addAlert.runModal() == .alertFirstButtonReturn {
                let command = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let profile = profilePopup.titleOfSelectedItem ?? ""
                if !command.isEmpty && !profile.isEmpty {
                    AppProfileBindingManager.shared.addBinding(command: command, profileName: profile)
                }
            }
        } else if response == .alertSecondButtonReturn {
            // Install shell script
            do {
                let scriptPath = try AppProfileBindingManager.shared.installShellIntegration()
                let successAlert = NSAlert()
                successAlert.messageText = "Shell Integration Installed"
                successAlert.informativeText = "Add this to your .zshrc or .bashrc:\n\nsource \"\(scriptPath.path)\"\n\nThis replaces any manual AWS_PROFILE exports or wrapper functions for bound commands."
                successAlert.alertStyle = .informational
                successAlert.addButton(withTitle: "OK")
                successAlert.runModal()
            } catch {
                showError("Installation Failed", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    @objc private func installCLI() {
        // Show a confirmation dialog first
        let confirmAlert = NSAlert()
        confirmAlert.messageText = "Install CLI Companion"
        confirmAlert.informativeText = "This will install the 'gateway' command to /usr/local/bin. Continue?"
        confirmAlert.alertStyle = .informational
        confirmAlert.addButton(withTitle: "Install")
        confirmAlert.addButton(withTitle: "Cancel")

        let response = confirmAlert.runModal()
        if response == .alertSecondButtonReturn {
            return // User canceled
        }

        // Use ScriptManager to install the command
        do {
            let message = try ScriptManager.shared.installGatewayCommand()

            // Show success feedback
            let alert = NSAlert()
            alert.messageText = "Terminal Command Installation"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            // Show error feedback
            let alert = NSAlert()
            alert.messageText = "Installation Failed"
            alert.informativeText = "Failed to install the gateway command: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }


    @objc private func installGatewayCommand() {
        do {
            let message = try ScriptManager.shared.installGatewayCommand()

            // Show success feedback
            let alert = NSAlert()
            alert.messageText = "Terminal Command Installation"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            // Show error feedback
            let alert = NSAlert()
            alert.messageText = "Installation Failed"
            alert.informativeText = "Failed to install the gateway command: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Notification Handlers

    @MainActor
    @objc private func handleProfilesUpdated() {
        buildMenu()
    }

    @MainActor
    @objc private func handleProfileConnected(_ notification: Notification) {
        if let profile = notification.userInfo?[Constants.NotificationKeys.profile] as? AWSProfile {
            activeProfile = profile.name

            // Mark this profile as connected
            ProfileHistoryManager.shared.setConnectedProfile(profile.name)
        }
    }

    @MainActor
    @objc private func handleSessionExpired(_ notification: Notification) {
        // If a specific profile expired, only handle that one
        if let profileName = notification.userInfo?[Constants.NotificationKeys.profileName] as? String {
            ProfileHistoryManager.shared.setProfileDisconnected(profileName)
            if activeProfile == profileName {
                activeProfile = ProfileHistoryManager.shared.getConnectedProfileOriginalName()
            }
        } else {
            // Legacy: all sessions expired
            ProfileHistoryManager.shared.clearConnectedProfile()
            activeProfile = nil
        }
        buildMenu()
    }

    // MARK: - Token Expiration Handling

    /// Handles token expiration warnings with cooldown to prevent duplicates
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

        // Check cooldown — don't fire duplicate notifications within 60s for same profile+level
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

    /// Shows a notification when a token has expired
    private func showTokenExpiredNotification(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "AWS CLI Gateway"
        content.body = "Your AWS SSO session for '\(profileName)' has expired. Please refresh to continue."
        content.sound = .default

        // Add action buttons
        let refreshAction = UNNotificationAction(
            identifier: "refresh-action",
            title: "Refresh Session",
            options: [.foreground]
        )

        let ignoreAction = UNNotificationAction(
            identifier: "ignore-action",
            title: "Ignore",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "token-expired",
            actions: [refreshAction, ignoreAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "token-expired"
        content.userInfo = ["profileName": profileName]

        let request = UNNotificationRequest(
            identifier: "token-expired-\(profileName)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("MenuBarManager: Failed to show token expired notification: \(error)")
            }
        }
    }

    /// Shows a notification when a token is about to expire
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

        // Add action buttons
        let refreshAction = UNNotificationAction(
            identifier: "refresh-action",
            title: "Refresh Now",
            options: [.foreground]
        )

        let remindLaterAction = UNNotificationAction(
            identifier: "remind-later-action",
            title: "Remind Later",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "token-expiring",
            actions: [refreshAction, remindLaterAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "token-expiring"
        content.userInfo = ["profileName": profileName]

        let request = UNNotificationRequest(
            identifier: "token-expiring-\(profileName)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("MenuBarManager: Failed to show token expiring notification: \(error)")
            }
        }
    }

    /// Refreshes the SSO session for the current active profile
    func refreshCurrentSession() {
        guard let activeProfile = self.activeProfile else {
            Task { @MainActor in
                showError("No Active Profile", message: "No profile is currently active.")
            }
            return
        }

        Task {
            let success = await SessionManager.shared.refreshSSOSession(for: activeProfile)
            await MainActor.run {
                if success {
                    // Session refreshed successfully - the SessionManager will handle UI updates
                    print("MenuBarManager: Successfully refreshed session for \(activeProfile)")
                } else {
                    // Failed to refresh - show user guidance
                    showError("Session Refresh Failed",
                             message: "Unable to refresh your SSO session automatically. Please run 'aws sso login --profile \(activeProfile)' in Terminal or reconnect using the app menu.")
                }
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func showError(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func calculateTextWidth(_ text: String, withFont font: NSFont) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size.width + 10
    }
}

extension NSTextField {
    func centerTextVertically() {
        let height = bounds.height
        let frame = NSRect(x: 0, y: (height - 17) / 2, width: bounds.width, height: 17)
        self.frame = frame
    }
}
