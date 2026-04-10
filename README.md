# Secret Chat

A local area network (LAN) messaging application that allows you to chat with friends and colleagues without an internet connection.

## 🌟 Features

- **No Internet Required** - Chat over your local WiFi or mobile hotspot
- **Privacy Focused** - Messages stay on your local network, never sent to external servers
- **Multiple Security Options** - Protect your rooms with:
  - Passwords
  - PIN codes
  - Pattern locks (Android-style 9-dot pattern)
- **Authentication** - Biometric or screen lock protection for the entire app
- **Customizable** - Dark/light theme support
- **Hidden Rooms** - Create private rooms that don't appear in room lists
- **Lightweight** - Minimal dependencies for fast performance
- **Material Design 3** - Modern, clean user interface

## 📱 How to Use

### As a Host
1. Tap **"Host Network"** to share your phone's hotspot or WiFi
2. Enter your display name
3. Create a room with an optional password, PIN, or pattern lock
4. Share the room name and credentials with others
5. Start chatting

### As a Guest
1. Tap **"Use Wi-Fi"** to join an existing network
2. Enter your display name
3. Browse available rooms or join a hidden room by name
4. Authenticate with the room's security if required
5. Start chatting

## 🔒 Security

- **Local-Only Communication** - All data stays on your local network
- **No Cloud Storage** - Messages are not stored on servers
- **Message Clearing** - Messages are automatically cleared when the app closes
- **Device Lock** - Optional app-level biometric or screen lock
- **Room Security** - Password, PIN, or pattern protection for individual rooms
- **Hidden Rooms** - Create private rooms not visible in room lists

## 🛠️ Building from Source

### Requirements
- Flutter SDK 3.11.4 or higher
- Android SDK 21+
- Gradle 8.14+

### Setup
```bash
# Clone the repository
git clone https://github.com/nihaltp/secret_chat.git
cd secret_chat

# Install dependencies
flutter pub get

# Run the app
flutter run

# Build APK for F-Droid
flutter build apk --split-per-abi
```

### Build Variants
- **Debug**: `flutter run`
- **Release**: `flutter build apk --release`
- **APK Split**: `flutter build apk --split-per-abi`

## 📋 Architecture

### Core Modules
- **Chat System** - LAN discovery and message routing
- **Security** - Authentication and room protection
- **Platform** - Android-specific features (hotspot settings)
- **UI/Screens** - Flutter material design screens

### Key Dependencies
- `connectivity_plus` - Network state detection
- `local_auth` - Biometric authentication
- `shared_preferences` - Local settings storage

## 🧪 Testing

Run the test suite:
```bash
flutter test
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🐛 Issues & Support

If you find any issues or have suggestions, please open an issue on GitHub.

## 📝 Notes

- This app is designed for local network communication only
- Compatible with Android 5.0 (API 21) and above
- Works with both WiFi and mobile hotspot networks
- No internet connection required for chatting

## 🎯 Roadmap

- [ ] Message file sharing
- [ ] Voice messaging
- [ ] Custom theme colors
- [ ] Message reactions
- [ ] Room descriptions and avatars
