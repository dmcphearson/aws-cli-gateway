import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case profiles = "Profiles"
    case tools = "Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .profiles: return "person.2"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

struct SettingsView: View {
    let onClose: () -> Void
    @State private var selectedSection: SettingsSection = .profiles

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            switch selectedSection {
            case .profiles:
                ProfilesSection(onClose: onClose)
            case .tools:
                ToolsSection()
            }
        }
        .frame(minWidth: 650, minHeight: 450)
    }
}

// MARK: - Profiles Section

enum ProfileAddMode: String, CaseIterable {
    case sso = "SSO Profile"
    case iam = "IAM Role"
    case advanced = "Advanced"
}

enum ProfileViewState {
    case list
    case rawConfig
    case addSSO
    case addIAM
}

struct ProfilesSection: View {
    let onClose: () -> Void
    @State private var profiles: [AWSProfile] = []
    @State private var selectedProfile: String?
    @State private var viewState: ProfileViewState = .list
    @State private var configText: String = ""
    @State private var configSaveMessage: String?

    private var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/config").path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if viewState == .addSSO || viewState == .addIAM {
                    Button(action: { viewState = .list }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 13))
                        }
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Text(viewState == .addSSO ? "Add SSO Profile" : "Add IAM Role")
                        .font(.headline)

                    Spacer()
                } else {
                    Text("Profiles")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: {
                        if viewState == .rawConfig {
                            viewState = .list
                        } else {
                            configText = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
                            viewState = .rawConfig
                        }
                    }) {
                        Image(systemName: viewState == .rawConfig ? "list.bullet" : "curlybraces")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help(viewState == .rawConfig ? "Show profile list" : "Show raw config")

                    Menu {
                        Button("SSO Profile") { viewState = .addSSO }
                        Button("IAM Role") { viewState = .addIAM }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            switch viewState {
            case .list:
                profileListView
            case .rawConfig:
                rawConfigView
            case .addSSO:
                SSOProfileTab(onClose: {
                    viewState = .list
                    loadProfiles()
                })
            case .addIAM:
                IAMRoleTab(onClose: {
                    viewState = .list
                    loadProfiles()
                })
            }
        }
        .onAppear { loadProfiles() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name(Constants.Notifications.profilesUpdated))) { _ in
            loadProfiles()
        }
    }

    private var profileListView: some View {
        VStack(spacing: 0) {
            List(selection: $selectedProfile) {
                ForEach(profiles, id: \.name) { profile in
                    ProfileListRow(profile: profile)
                        .tag(profile.name)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        deleteProfile(profiles[index].name)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                Button(action: { deleteSelected() }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedProfile == nil)

                Spacer()

                Text("\(profiles.count) profile\(profiles.count == 1 ? "" : "s") configured")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var rawConfigView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(configPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if let msg = configSaveMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(msg.contains("Error") ? .red : .green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            TextEditor(text: $configText)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Revert") {
                    configText = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
                    configSaveMessage = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Save") { saveConfig() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func loadProfiles() {
        profiles = ConfigManager.shared.getProfiles()
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func deleteSelected() {
        guard let name = selectedProfile else { return }
        deleteProfile(name)
    }

    private func deleteProfile(_ name: String) {
        ConfigManager.shared.deleteProfile(name)
        NotificationCenter.default.post(name: Notification.Name(Constants.Notifications.profilesUpdated), object: nil)
        selectedProfile = nil
        loadProfiles()
    }

    private func saveConfig() {
        do {
            try configText.write(toFile: configPath, atomically: true, encoding: .utf8)
            configSaveMessage = "Saved"
            NotificationCenter.default.post(name: Notification.Name(Constants.Notifications.profilesUpdated), object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { configSaveMessage = nil }
        } catch {
            configSaveMessage = "Error: \(error.localizedDescription)"
        }
    }
}

struct ProfileListRow: View {
    let profile: AWSProfile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile is SSOProfile ? "person.badge.key" : "key")
                .foregroundColor(profile is SSOProfile ? .blue : .orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 13, weight: .medium))

                if let sso = profile as? SSOProfile {
                    Text("\(sso.accountId) \u{2022} \(sso.roleName)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if let iam = profile as? IAMProfile {
                    Text("Source: \(iam.sourceProfile) \u{2022} \(iam.roleArn.components(separatedBy: "/").last ?? "")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(profile is SSOProfile ? "SSO" : "IAM")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
        }
        .padding(.vertical, 3)
    }
}


// MARK: - Tools Section

struct ToolsSection: View {
    @State private var installMessage: String?
    @State private var cacheMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tools")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Gateway CLI
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .font(.title3)
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Gateway CLI")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Installs `gateway` to /usr/local/bin for running AWS commands with your active profile.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Button("Install Gateway CLI") { installGatewayCLI() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                if let msg = installMessage {
                                    Text(msg)
                                        .font(.system(size: 11))
                                        .foregroundColor(msg.contains("Error") ? .red : .green)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(4)
                    }

                    // Clear Cache
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Clear AWS Cache")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Removes all cached credentials from ~/.aws/cli/cache and ~/.aws/sso/cache. Disconnects all active sessions.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Button("Clear Cache") { clearCache() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                if let msg = cacheMessage {
                                    Text(msg)
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(4)
                    }
                }
                .padding(20)
            }
        }
    }

    private func installGatewayCLI() {
        do {
            let message = try ScriptManager.shared.installGatewayCommand()
            installMessage = message
        } catch {
            installMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func clearCache() {
        do {
            let message = try ScriptManager.shared.clearAWSCache()
            SessionManager.shared.cleanDisconnect()
            ProfileHistoryManager.shared.clearConnectedProfile()
            cacheMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { cacheMessage = nil }
        } catch {
            cacheMessage = "Error: \(error.localizedDescription)"
        }
    }
}
