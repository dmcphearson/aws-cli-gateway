import SwiftUI

struct ProfilesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [AWSProfile] = []
    @State private var selectedProfile: AWSProfile?
    @State private var connectedProfileId: String? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .padding()
            } else {
                List(profiles, id: \.name) { profile in
                    ProfileRow(
                        profile: profile,
                        isSelected: selectedProfile?.name == profile.name,
                        isConnected: isProfileConnected(profile),
                        onToggleConnection: {
                            toggleConnection(profile)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProfile = profile
                    }
                    .contextMenu {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(profile.name, forType: .string)
                        } label: {
                            Label("Copy Profile Name", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteProfile(profile)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .frame(minHeight: 200)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(spacing: 12) {
                Button("Add Profile") {
                    WindowManager.shared.showAddProfileWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            loadProfiles()
            updateConnectedProfile()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name(Constants.Notifications.profilesUpdated)
            )
        ) { _ in
            loadProfiles()
            updateConnectedProfile()
        }
    }
    
    private func toggleConnection(_ profile: AWSProfile) {
        // Check if this profile is already connected
        let isAlreadyConnected = isProfileConnected(profile)

        if isAlreadyConnected {
            // Disconnect this profile
            ProfileHistoryManager.shared.clearConnectedProfile()
            SessionManager.shared.stopMonitoring()
        } else {
            // Connect to this profile (reuse your existing connect logic)
            isLoading = true
            errorMessage = nil
            selectedProfile = profile

            Task {
                do {
                    if profile is SSOProfile {
                        // Login to SSO
                        let loginArgs = ["sso", "login", "--profile", profile.name]
                        _ = try await CommandRunner.shared.runCommand("aws", args: loginArgs)
                    }

                    // Verify with STS
                    let verifyArgs = ["sts", "get-caller-identity", "--profile", profile.name]
                    _ = try await CommandRunner.shared.runCommand("aws", args: verifyArgs)

                    await MainActor.run {
                        // Use the correct method signature - only profile name without withId
                        ProfileHistoryManager.shared.setConnectedProfile(profile.name)

                        // Post notification
                        NotificationCenter.default.post(
                            name: Notification.Name(Constants.Notifications.profileConnected),
                            object: nil,
                            userInfo: [Constants.NotificationKeys.profile: profile]
                        )

                        // Start session monitoring
                        SessionManager.shared.startMonitoring(for: profile.name)

                        // Update UI status
                        updateConnectedProfile()
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = Constants.ErrorMessages.ssoLoginFailed
                    }
                }

                await MainActor.run {
                    isLoading = false
                }
            }
        }

        // Update UI
        updateConnectedProfile()

        // Post notification for other components
        NotificationCenter.default.post(
            name: Notification.Name(Constants.Notifications.profilesUpdated),
            object: nil
        )
    }

    private func loadProfiles() {
        profiles = ConfigManager.shared.getProfiles()
    }

    private func updateConnectedProfile() {
        if let connectedProfile = ProfileHistoryManager.shared.getConnectedProfile() {
            connectedProfileId = connectedProfile.id
        } else {
            connectedProfileId = nil
        }
    }

    private func isProfileConnected(_ profile: AWSProfile) -> Bool {
        if let connectedProfile = ProfileHistoryManager.shared.getConnectedProfile() {
            return connectedProfile.originalName == profile.name
        }
        return false
    }

    private func connectToProfile(_ profile: AWSProfile) {
        isLoading = true
        errorMessage = nil
        selectedProfile = profile

        Task {
            do {
                if profile is SSOProfile {
                    // Login to SSO
                    let loginArgs = ["sso", "login", "--profile", profile.name]
                    _ = try await CommandRunner.shared.runCommand("aws", args: loginArgs)
                }

                // Verify with STS for both profile types
                let verifyArgs = ["sts", "get-caller-identity", "--profile", profile.name]
                _ = try await CommandRunner.shared.runCommand("aws", args: verifyArgs)

                await MainActor.run {
                    // Set as connected profile in ProfileHistoryManager
                    ProfileHistoryManager.shared.setConnectedProfile(profile.name)

                    // Post notification for other components
                    NotificationCenter.default.post(
                        name: Notification.Name(Constants.Notifications.profileConnected),
                        object: nil,
                        userInfo: [Constants.NotificationKeys.profile: profile]
                    )

                    // Start session monitoring for this profile
                    SessionManager.shared.startMonitoring(for: profile.name)

                    // Update UI status
                    updateConnectedProfile()

                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = Constants.ErrorMessages.ssoLoginFailed
                    selectedProfile = nil
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func deleteProfile(_ profile: AWSProfile) {
        // Check if this is the currently connected profile
        let isConnected = isProfileConnected(profile)

        // Delete the profile
        ConfigManager.shared.deleteProfile(profile.name)

        // If it was connected, stop session monitoring
        if isConnected {
            SessionManager.shared.stopMonitoring()
            // Clear connected profile
            ProfileHistoryManager.shared.clearConnectedProfile()
        }

        // Reload profiles and notify
        loadProfiles()
        updateConnectedProfile()

        NotificationCenter.default.post(
            name: Notification.Name(Constants.Notifications.profilesUpdated),
            object: nil
        )
    }
}

struct ProfileRow: View {
    let profile: AWSProfile
    let isSelected: Bool
    let isConnected: Bool
    let onToggleConnection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if isConnected {
                        Text("Connected")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.gradient, in: Capsule())
                    }
                }

                if let ssoProfile = profile as? SSOProfile {
                    Text("\(ssoProfile.accountId) - \(ssoProfile.roleName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let iamProfile = profile as? IAMProfile {
                    Text("IAM Role - \(iamProfile.roleArn)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onToggleConnection) {
                Image(systemName: isConnected ? "star.fill" : "star")
                    .foregroundStyle(isConnected ? .yellow : .secondary)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.quaternary, lineWidth: 0.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(.thinMaterial.opacity(isSelected ? 1.0 : 0.0), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? .secondary.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}


#Preview {
    ProfilesView()
}
