import Foundation

class CommandRunner {
    static let shared = CommandRunner()

    // Cache the AWS CLI path
    private let awsCliPath: String

    private init() {
        // Find AWS CLI path once at initialization
        let paths = ["/usr/local/bin/aws", "/opt/homebrew/bin/aws", "/usr/bin/aws"]
        self.awsCliPath = paths.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/local/bin/aws"
        print("CommandRunner: Using AWS CLI at: \(self.awsCliPath)")
    }

    func runCommand(_ command: String, args: [String]) async throws -> String {
        // Early feedback for UI responsiveness
        print("Preparing command: \(command) \(args.joined(separator: " "))")

        // If this is an AWS command with a profile, check token expiration first
        // Skip token checks for SSO login commands to prevent infinite loops
        if command == "aws", let profileIndex = args.firstIndex(of: "--profile"),
           profileIndex + 1 < args.count,
           !(args.contains("sso") && args.contains("login")) {
            let profileName = args[profileIndex + 1]

            // Check if the token is expired or about to expire
            let tokenIsValid = await SessionManager.shared.checkTokenExpiration(for: profileName)

            if !tokenIsValid {
                // Try to refresh the session automatically for non-critical commands
                if !args.contains("sts") || !args.contains("get-caller-identity") {
                    print("CommandRunner: Token expired/expiring for profile \(profileName), attempting refresh...")
                    let refreshed = await SessionManager.shared.refreshSSOSession(for: profileName)
                    if !refreshed {
                        throw NSError(
                            domain: "CommandRunner",
                            code: 403,
                            userInfo: [
                                NSLocalizedDescriptionKey: "AWS SSO token has expired. Please refresh your session using the app menu or run 'aws sso login --profile \(profileName)'."
                            ]
                        )
                    }
                } else {
                    // For sts get-caller-identity, just proceed - it's used for checking token validity
                    print("CommandRunner: Proceeding with token check command despite expiration")
                }
            }
        }

        // Create the process
        let process = Process()
        let executablePath = command == "aws" ? self.awsCliPath : "/usr/local/bin/\(command)"
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Start the process
        print("Running command: \(command) \(args.joined(separator: " "))")
        try process.run()

        // Create a separate task to read output while the process runs
        // This avoids concurrency issues and Swift 6 warnings
        let outputTask = Task.detached {
            let outputHandle = outputPipe.fileHandleForReading
            var output = ""

            repeat {
                let data = outputHandle.availableData
                if data.isEmpty { break }

                if let str = String(data: data, encoding: .utf8) {
                    print(str)
                    output += str
                }
            } while true

            return output
        }

        // Same for error output
        let errorTask = Task.detached {
            let errorHandle = errorPipe.fileHandleForReading
            var errorOutput = ""

            repeat {
                let data = errorHandle.availableData
                if data.isEmpty { break }

                if let str = String(data: data, encoding: .utf8) {
                    print("Error: \(str)")
                    errorOutput += str
                }
            } while true

            return errorOutput
        }

        // Wait for process to complete
        process.waitUntilExit()

        // Get results from our detached tasks
        let outputString = await outputTask.value
        let errorString = await errorTask.value

        // Check exit status
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "CommandRunner",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorString.isEmpty
                        ? "Command failed with no error output" : errorString
                ]
            )
        }

        return outputString
    }

    func login(profileName: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                _ = try await runCommand("aws", args: ["sso", "login", "--profile", profileName])
                completion(true)
            } catch {
                print("Login error: \(error)")
                completion(false)
            }
        }
    }
}
