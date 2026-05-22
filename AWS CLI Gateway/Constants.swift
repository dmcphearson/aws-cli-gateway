import Foundation

enum Constants {
    static let appName = "AWS SSO Gateway"

    // MARK: - File Paths
    enum Paths {
        static let awsConfigDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws")
        static let awsConfigFile = awsConfigDirectory
            .appendingPathComponent("config")
        static let awsCredentialsFile = awsConfigDirectory
            .appendingPathComponent("credentials")
        static let awsCliCacheDirectory = awsConfigDirectory
            .appendingPathComponent("cli/cache")

        static let appSupportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(appName)

        static let profilesStore = appSupportDirectory?
            .appendingPathComponent("profiles.json")
    }

    // MARK: - Notifications
    enum Notifications {
        static let sessionMonitoringStopped = "me.mcphearson.aws-cli-gateway.sessionMonitoringStopped"
        static let sessionTimeUpdated = "me.mcphearson.aws-cli-gateway.sessionTimeUpdated"
        static let sessionWarning = "me.mcphearson.aws-cli-gateway.sessionWarning"
        static let sessionExpired = "me.mcphearson.aws-cli-gateway.sessionExpired"
        static let sessionRenewed = "me.mcphearson.aws-cli-gateway.sessionRenewed"
        static let profilesUpdated = "me.mcphearson.aws-cli-gateway.profilesUpdated"
        static let profileConnected = "me.mcphearson.aws-cli-gateway.profileConnected"
    }

    // MARK: - Notification Keys
    enum NotificationKeys {
        static let profileName = "profileName"
        static let profile = "profile"
        static let timeRemaining = "timeRemaining"
        static let threshold = "threshold"
    }

    // MARK: - Session Monitoring
    enum Session {
        static let warningThresholds: [TimeInterval] = [3600, 1800, 600, 300, 60]
    }

    // MARK: - Error Messages
    enum ErrorMessages {
        static let profileValidation = "Please ensure all fields are filled correctly"
        static let ssoLoginFailed = "SSO login failed. Please try again"
    }

    // MARK: - AWS
    struct AWS {
        static let outputFormats = ["json", "yaml", "text", "table"]
    }
}
