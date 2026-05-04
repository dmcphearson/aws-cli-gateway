import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.standardPadding) {
            headerSection

            Group {
                if let currentProfile = viewModel.currentProfile {
                    activeProfileSection(profileName: currentProfile)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                } else {
                    noProfileSection
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.currentProfile)

            statusSection

            Spacer()
        }
        .padding(Constants.UI.standardPadding)
        .frame(
            width: Constants.UI.profilesWindow.width,
            height: Constants.UI.profilesWindow.height
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        Text(Constants.appName)
            .font(.title)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
    }
    
    private func activeProfileSection(profileName: String) -> some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            Text("Connected to profile: \(profileName)")
                .font(.headline)
                .foregroundStyle(.primary)

            if let timeRemaining = viewModel.sessionTimeRemaining {
                Text(timeRemaining)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Renew Session") {
                viewModel.renewSession()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(viewModel.sessionStatus == Constants.Session.sessionExpired)
        }
        .padding(16)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
    
    private var noProfileSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.smallPadding) {
            Text("No profile connected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Add Profile") {
                viewModel.showAddProfileWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
    
    private var statusSection: some View {
        StatusIndicator(status: viewModel.sessionStatus)
            .padding(.top, Constants.UI.smallPadding)
    }
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
}
