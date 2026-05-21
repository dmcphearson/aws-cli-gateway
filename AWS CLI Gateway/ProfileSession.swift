import Foundation

struct ProfileSession {
    let profileName: String
    var roleCredExpiryDate: Date?
    var ssoTokenExpiryDate: Date?
    var lastHealthCheck: Date?
    var status: ProfileSessionStatus
    var cacheFileName: String?

    /// The real session lifetime is the SSO token — role credentials auto-refresh
    /// as long as the SSO token is valid. Only fall back to role cred expiry if
    /// we can't determine the SSO token expiry.
    var effectiveExpiry: Date? {
        if let sso = ssoTokenExpiryDate {
            return sso
        }
        return roleCredExpiryDate
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
    case expiringSoon
    case expired
    case error(String)

    static func == (lhs: ProfileSessionStatus, rhs: ProfileSessionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.connecting, .connecting), (.active, .active),
             (.expiringSoon, .expiringSoon), (.expired, .expired):
            return true
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}
