import Foundation

struct ProfileSession {
    let profileName: String
    var roleCredExpiryDate: Date?
    var ssoTokenExpiryDate: Date?
    var lastHealthCheck: Date?
    var status: ProfileSessionStatus
    var cacheFileName: String?

    /// Role credentials reflect the permission set duration (actual usable session).
    /// The SSO access token (60min) auto-refreshes via refresh token — don't use it
    /// as the countdown. Fall back to SSO token only if role creds aren't available.
    var effectiveExpiry: Date? {
        if let role = roleCredExpiryDate {
            return role
        }
        return ssoTokenExpiryDate
    }

    var timeRemaining: TimeInterval {
        guard let expiry = effectiveExpiry else { return 0 }
        return max(0, expiry.timeIntervalSinceNow)
    }

    var formattedTimeRemaining: String {
        let remaining = timeRemaining
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

enum ProfileSessionStatus: Equatable {
    case connecting
    case active
    case expired
    case error(String)

    static func == (lhs: ProfileSessionStatus, rhs: ProfileSessionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.connecting, .connecting), (.active, .active),
             (.expired, .expired):
            return true
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
