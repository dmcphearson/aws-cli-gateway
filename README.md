# AWS CLI Gateway

<p align="center">
    <img src="AWS CLI Gateway/Assets.xcassets/AppIcon.appiconset/aws-cli-gateway-app-icon-iOS-Default-512x512@1x.png" width="128">
</p>

## Overview

A macOS menu bar application for managing AWS SSO profiles and sessions. Monitor multiple concurrent sessions, get proactive expiry warnings, and run AWS CLI commands without manually specifying profiles.

## Features

### Multi-Profile Session Management
- Monitor up to 5 concurrent AWS SSO sessions
- Per-profile countdown timers with automatic refresh
- Proactive credential refresh 15 minutes before expiry
- Health checks via `sts get-caller-identity` every 5 minutes
- Session restore on app launch

### Interactive Menu Bar Panel
- Floating NSPanel with SwiftUI interface (replaces legacy NSMenu)
- Expandable profile detail showing region, account, and expiry info
- One-click connect, disconnect, and refresh per profile
- Color-coded status: green (active), red (expired), gray (disconnected)

### Profile Management
- **SSO Profiles**: Create profiles with permission set management
- **IAM Role Profiles**: Assume roles from source SSO profiles
- **App-to-Profile Binding**: Bind specific commands (e.g., `terraform`, `npm`) to profiles via `AWS_PROFILE` injection

### Terminal Integration
- `gateway` CLI command routes AWS commands through your connected profile
- `gateway list sso` / `gateway list role` for quick profile enumeration
- `gateway debug` for troubleshooting

### Notifications
- Per-profile expiry warnings with configurable thresholds
- Notification deduplication (60s cooldown per profile)
- "Refresh" action button directly on notifications

## Installation

Download the latest release from the [Releases](https://github.com/dmcphearson/aws-cli-gateway/releases) page and move the `.app` to your Applications folder.

### Build from Source

Requires Xcode 16+ and macOS 15.2+.

```bash
git clone https://github.com/dmcphearson/aws-cli-gateway.git
cd aws-cli-gateway
./build.sh
```

The built app appears in `output/AWS CLI Gateway.app`. To install:

```bash
cp -R "output/AWS CLI Gateway.app" /Applications/
```

To sign with your own Developer ID:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name" ./build.sh
```

## Terminal Integration

Install the `gateway` command from the menu bar: **Tools & Settings > Install CLI Tools**.

```bash
# Run AWS commands with your connected profile
gateway s3 ls
gateway ec2 describe-instances

# List available profiles
gateway list
gateway list sso
gateway list role

# Debug information
gateway debug
```

## Requirements

- macOS 15.2 (Sequoia) or later
- AWS CLI v2 installed and configured
- AWS SSO configured for your organization

## Contributing

Contributions are welcome. Please open an issue or pull request.

## License

See [LICENSE](LICENSE) for details.
