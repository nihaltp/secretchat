# Changelog

All notable changes to this project will be documented in this file.

## v1.1.3 - 2026-04-12

- Direct user chat now uses dedicated transport channels:
  - userDiscoveryPort (48652) for discovery
  - userChatPort (48653) for direct messaging
  - room traffic remains isolated on roomDiscoveryPort/roomChatPort
- Added direct-chat fallback flow:
  - Tapping a user can now start a direct thread immediately even when no peer-hosted direct room is currently discoverable.
- Improved Network Overview usability:
  - Active room cards can be tapped to jump back into that room.
  - Current device/user is filtered out of the network users list.
- Test coverage updates:
  - Added/updated direct chat port integration and network overview tests.
  - Full suite passing after these changes.

## v1.1.2 - 2026-04-11
- Added default room listening flow for easier app startup into available rooms.
- Improved stability and code consistency in chat controllers and related tests.
- Tuned Android release settings for more reliable release builds.
- Added release automation script for split-ABI APK packaging and F-Droid handoff.

## v1.1.1
- Version bump and maintenance updates.

## v1.1.0
- Optional chat history per room.
- Sender-owned history sync on rejoin.
- Join and leave notices auto-hide after 5 seconds.
- Message access restricted to user presence windows.
- Host failover on Wi-Fi to the highest battery device.
- Leaving user messages are purged from all devices.

## v1.0.0
- Initial release of Secret Chat.
- LAN messaging without internet connection.
- Multiple authentication options (password, PIN, pattern lock).
- App-level biometric security.
- Dark theme support.
- Hidden rooms for privacy.
