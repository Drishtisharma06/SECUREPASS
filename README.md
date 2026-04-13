**###🚀 SecurePass – Secure Password Vault**

SecurePass is a modern Flutter-based password manager that uses passwordless OTP authentication and strong encryption to securely store and manage your credentials — all locally on your device.

**🔐 Key Highlights**
🔑 Passwordless Authentication (Email OTP login)
🛡 AES-256 Encryption for all stored passwords
📱 Fully Local Storage (No server required)
⚡ Fast & Lightweight Flutter App
☁️ Optional Firebase Backup Support
**✨ Features**
🔓 Authentication
Email-based login/signup with OTP
6-digit OTP generated & verified locally
OTP expires in 3 minutes with resend timer
Debug mode shows OTP for testing
Automatic account creation on first login
**🔑 Password Vault**
Secure encrypted password storage
Add, edit, delete, and search entries
Store:
Title
Username / Email
Password (encrypted)
One-tap copy to clipboard
Show/hide password toggle
**⚙️ Password Generator**
Custom length (8–32 characters)
Include:
Uppercase
Lowercase
Numbers
Special characters
Preview before saving
**🔒 Security & Storage**
AES-256-CBC encryption
Key derived from user email (SHA-256)
Stored using SharedPreferences
Auto logout after inactivity
Separate vault per user
**☁️ Optional Cloud Support**
Firebase Firestore integration
Backup & restore capability (if enabled)
**🛠 Tech Stack**
Flutter (Frontend)
Dart
SharedPreferences (Local Storage)
Firebase (Optional)
encrypt + crypto packages
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


## License

MIT License - See LICENSE file for details
