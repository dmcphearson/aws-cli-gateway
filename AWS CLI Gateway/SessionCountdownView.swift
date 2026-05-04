import SwiftUI

struct SessionCountdownView: View {
    // Start with a default value before notifications arrive
    @State private var timeRemaining: TimeInterval = 0
    @State private var sessionStatus: SessionStatus = .unknown
    @State private var connectedProfile: String? = nil
    @State private var isRenewing: Bool = false

    enum SessionStatus {
        case active
        case expired
        case notAuthenticated
        case unknown
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator with pulsing animation
            Circle()
                .fill(statusColor.gradient)
                .frame(width: 10, height: 10)
                .scaleEffect(sessionStatus == .active ? 1.0 : 0.8)
                .opacity(sessionStatus == .active ? 1.0 : 0.7)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: sessionStatus == .active)

            // Profile and timer
            VStack(alignment: .leading, spacing: 2) {
                if let profileName = connectedProfile {
                    Text(profileName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }

                if sessionStatus == .active && timeRemaining > 0 {
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            // Refresh button with hover effects
            if sessionStatus == .expired || sessionStatus == .notAuthenticated {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        renewSession()
                    }
                }) {
                    Image(systemName: isRenewing ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(isRenewing ? 360 : 0))
                        .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isRenewing)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRenewing)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.quaternary, lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sessionStatus)
        .onAppear {
            // Get initial profile
            updateConnectedProfile()

            // Set up observer to get the active profile on changes
            NotificationCenter.default.addObserver(
                forName: Notification.Name(Constants.Notifications.profilesUpdated),
                object: nil,
                queue: .main
            ) { _ in
                updateConnectedProfile()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name(Constants.Notifications.sessionTimeUpdated)
            )
        ) { notification in
            if let remaining = notification.userInfo?[Constants.NotificationKeys.timeRemaining] as? TimeInterval {
                self.timeRemaining = remaining
                self.sessionStatus = .active
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name(Constants.Notifications.sessionExpired)
            )
        ) { _ in
            self.sessionStatus = .expired
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name(Constants.Notifications.sessionMonitoringStopped)
            )
        ) { _ in
            self.sessionStatus = .notAuthenticated
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name(Constants.Notifications.sessionRenewed)
            )
        ) { _ in
            self.isRenewing = false
            // Session status will be updated by the time notification
        }
    }

    private var statusColor: Color {
        switch sessionStatus {
        case .active:
            return Color.green
        case .expired:
            return Color.orange
        case .notAuthenticated, .unknown:
            return Color.gray
        }
    }

    private var statusText: String {
        switch sessionStatus {
        case .active:
            return "Session Active"
        case .expired:
            return "Session Expired"
        case .notAuthenticated:
            return "Not Authenticated"
        case .unknown:
            return "No Profile Selected"
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "Session: %02d:%02d:%02d", hours, minutes, seconds)
    }

    private func updateConnectedProfile() {
        if let profileInfo = ProfileHistoryManager.shared.getConnectedProfile() {
            self.connectedProfile = profileInfo.originalName

            // Start monitoring for this profile 
            SessionManager.shared.startMonitoring(for: profileInfo.originalName)
        } else {
            self.connectedProfile = nil
            self.sessionStatus = .notAuthenticated
        }
    }


    private func renewSession() {
        guard connectedProfile != nil else { return }

        isRenewing = true

        Task {
            do {
                try await SessionManager.shared.renewSession()
            } catch {
                // Handle error by reverting UI state
                DispatchQueue.main.async {
                    self.isRenewing = false
                }
            }
        }
    }
}
