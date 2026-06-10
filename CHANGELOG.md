# Changelog

## [2.0.0] - 2026-06-10

### Maintenance

- cabb851  chore: add fastlane

### Other

- 89d8b9a  change app name to secretchat

# Changelog

All notable changes to this project will be documented in this file.


## v1.2.1 - 2026-04-15

- Fixed message delivery between devices with different message padding settings (chunk size mismatch).
- Added cross-device tests for mismatched padding in both user and room chat.
- Improved failover test reliability (host readiness wait).
- All tests and analyzer clean for release.

## v1.2.0 - 2026-04-14

- Added Signal-style direct-chat E2EE foundation:
  - X3DH-style session bootstrap using Ed25519 identity keys and X25519 pre-keys.
  - Double Ratchet-style per-message AES-256-GCM key evolution for direct chat.
  - Volatile-only key/session lifecycle with explicit in-memory session wipe paths.
- Integrated direct-chat encryption wiring into controller flow:
  - peer bundle exchange on direct join/accept
  - encrypted direct message send/receive handling
  - direct-session cleanup on disconnect
- Added encryption test coverage:
  - handshake path, ratchet progression, bidirectional decrypt, and session clearing behavior.
- Updated SSOT docs with a dedicated E2EE model reference and architecture links.
- Improved debug startup responsiveness:
  - deferred heavy startup initialization after first frame
  - reduced redundant discovery restarts on duplicate connectivity callbacks
  - coalesced frequent controller-triggered UI refreshes to once-per-frame updates

## v1.1.5 - 2026-04-12

- Improved host failover reliability with a staged election flow:
  - Temporary host is selected immediately on host loss.
  - Temporary host runs a probe round and finalizes host selection using latency plus battery score.
  - Added dedicated failover scoring weights in `lib/chat/controllers/failover_weights.dart`.
- Strengthened failover validation:
  - Added `test/failover_weights_test.dart` for latency and battery scoring behavior.
- Lint and analyzer alignment updates across chat controllers, screens, and tests.

## v1.1.4 - 2026-04-12

- Refined direct-chat discovery and badge behavior:
  - Direct chat indicators now appear only after actual direct-message activity.
  - Hidden direct chats no longer advertise as soon as they are hosted.
  - Leaving a direct chat returns to Network Overview instead of Rooms.
- Kept room browsing focused on rooms only:
  - Direct chat entries are excluded from the Rooms screen.
  - Network Overview remains the place to discover and open direct chats.
- Validation updates:
  - Ran `flutter analyze` and `flutter test` successfully after the chat-flow changes.

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
