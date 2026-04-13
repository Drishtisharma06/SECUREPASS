# 🚀SECUREPASS - Secure Password Vault

A Flutter app with passwordless email OTP login and secure password vault management. All data is encrypted and stored locally on your device.

## Features

### ⚙️Authentication
- **Passwordless Login**: Email-based signup/login with OTP verification
- **Local OTP Generation**: 6-digit OTP generated and verified locally
- **OTP Expiration**: 3-minute expiration with resend countdown
- **Test Mode**: Debug mode displays generated OTP on the auth screen for easy testing
- **Automatic Account Creation**: New accounts created on first login
- **Account Recovery**: Login with the same email to restore all saved entries

### 🔑Password Vault
- **Secure Storage**: All passwords encrypted with AES-256-CBC encryption
- **Password Generator**: Built-in generator with customizable length (8-32 chars)
- **Character Types**: Choose uppercase, lowercase, numbers, and special characters
- **Password Preview**: Toggle visibility during generation for confirmation before saving
- **Entry Management**: Add, edit, delete, and search saved password entries
- **Entry Details**: Store title, username/email/ID, and encrypted password
- **Quick Actions**: Copy password to clipboard with one tap
- **Password Masking**: Hide/reveal saved passwords with toggle

### 🔒Security & Persistence
- **Local Encryption**: All entries encrypted with email-derived keys
- **Local Storage**: Entries saved in SharedPreferences (device storage only)
- **Cloud Sync**: Optional Firebase Firestore integration (enabled if available)
- **Auto Sign-Out**: Automatic logout after 5 minutes of inactivity
- **Session Management**: Separate vault per email account

## 🛠Tech Stack

- **Framework**: Flutter 3.41.6
- **Storage**: SharedPreferences (local) + Firebase Firestore (optional)
- **Encryption**: AES-256-CBC via the `encrypt` package
- **Authentication**: Passwordless OTP via Firebase (optional)

## Setup & Installation

### Prerequisites
- Flutter SDK 3.0.0 or higher
- Android SDK or iOS setup (depending on target platform)

### Steps

1. **Clone or navigate to the project**:
   ```bash
   cd PS_generator
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the app**:
   ```bash
   flutter run
   ```

### Testing

The app includes **test mode** for development:
- Enter any valid email (e.g., `test@example.com`)
- Tap "Send OTP"
- In debug builds, the generated 6-digit OTP displays in green on the auth screen
- Enter the displayed OTP to proceed

All data is saved locally on your device and restored when you log in with the same email again.

## Project Structure

```
lib/
├── main.dart           # Main app with OTP auth flow and password vault UI
├── firebase_options.dart  # Firebase configuration

pubspec.yaml          # Dependencies (Flutter, Firebase, Encryption)
README.md            # This file
```

## Dependencies

- `shared_preferences`: Local encrypted storage
- `firebase_core`: Firebase initialization
- `cloud_firestore`: Cloud backup (optional)
- `encrypt`: AES encryption for passwords
- `crypto`: SHA-256 hashing for secure key derivation

## Usage

### Login
1. Enter your email
2. Tap "Send OTP"
3. OTP displays in debug mode (green box)
4. Enter the 6-digit code
5. Enter your password vault

### Managing Passwords
- **Add**: Tap the `+` button to add a new entry
- **Generate**: Use the password generator with custom settings
- **Edit**: Tap the menu on any entry to edit or delete
- **Search**: Use the search bar to filter by title or username
- **Reveal**: Toggle password visibility with the eye icon
- **Copy**: Tap the copy icon to save password to clipboard

### Security Notes
- Passwords are encrypted with AES-256-CBC
- Encryption key derived from your email + salt
- Local storage only (device-specific)
- No plaintext passwords are stored or transmitted
- OTP is generated and verified locally (no backend needed)

## Future Enhancements

- Real email delivery for OTP (optional backend service)
- Biometric authentication support
- Cross-device sync via cloud backup
- Passkey support for modern authentication

## License

MIT License - See LICENSE file for details
