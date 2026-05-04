import SwiftUI

struct StatusIndicator: View {
    let status: String
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor.gradient)
                .frame(width: 10, height: 10)
                .scaleEffect(isActive ? (isAnimating ? 1.1 : 1.0) : 0.8)
                .opacity(isActive ? 1.0 : 0.7)
                .onAppear {
                    if isActive {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            isAnimating = true
                        }
                    }
                }
                .onChange(of: status) {
                    DispatchQueue.main.async {
                        if isActive {
                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                isAnimating = true
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isAnimating = false
                            }
                        }
                    }
                }

            Text(status)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: status)
    }

    private var isActive: Bool {
        status == Constants.Session.sessionActive
    }
    
    private var statusColor: Color {
        switch status {
        case Constants.Session.sessionActive:
            return .green
        case Constants.Session.sessionExpired:
            return .red
        default:
            return .secondary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusIndicator(status: Constants.Session.sessionActive)
        StatusIndicator(status: Constants.Session.sessionExpired)
        StatusIndicator(status: Constants.Session.noActiveSession)
    }
    .padding()
}
