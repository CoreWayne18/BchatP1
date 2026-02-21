# BChat — Native Android App
### Offline Bluetooth P2P Encrypted Chat · No Internet · No Hub Required

---

## What This Is

A **real Android APK** (built with Flutter) that lets two phones chat directly over
Bluetooth — no internet, no server, no hub phone, no nRF Connect.

Each phone runs the same app. One picks **HOST** (becomes a BLE peripheral),
the other picks **JOIN** (scans and connects). That's it.

```
Phone A (BChat APK)          Phone B (BChat APK)
   HOST → advertises    ←BLE→   JOIN → scans & connects
         ↑                              ↑
   GATT Peripheral              GATT Central
         └──────── AES-256-GCM encrypted ──────────┘
```

---

## Architecture

| Layer | Technology |
|-------|-----------|
| BLE Peripheral | `ble_peripheral` Flutter plugin (GATT server, advertise) |
| BLE Central | `flutter_blue_plus` Flutter plugin (scan, connect, notify) |
| Encryption | ECDH P-256 key exchange → AES-256-GCM (pointycastle, pure Dart) |
| Storage | SQLite via `sqflite` |
| State | `provider` |

---

## How to Build the APK

### Prerequisites (one-time install)

1. **Install Flutter SDK**
   ```bash
   # Download from https://docs.flutter.dev/get-started/install
   # Then add to PATH:
   export PATH="$PATH:/path/to/flutter/bin"
   flutter doctor   # verify everything is green
   ```

2. **Install Android Studio + Android SDK**
   - Download: https://developer.android.com/studio
   - In Android Studio → SDK Manager → install Android SDK 34
   - Accept licenses: `flutter doctor --android-licenses`

3. **Install Java 17** (required by Gradle)
   ```bash
   # Ubuntu/Debian:
   sudo apt install openjdk-17-jdk
   # macOS:
   brew install openjdk@17
   # Windows: download from https://adoptium.net
   ```

### Build steps

```bash
# 1. Clone / navigate to project
cd bchat_flutter

# 2. Get dependencies
flutter pub get

# 3. Build the APK
flutter build apk --release

# The APK is at:
# build/app/outputs/flutter-apk/app-release.apk
```

### Install on phone

```bash
# Option A — USB (with USB debugging enabled on the phone)
flutter install

# Option B — Copy the APK file to phone and tap it to install
# (Enable "Install from unknown sources" in phone settings)
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## How to Use the App

### Step 1 — Install on both phones
Transfer and install `app-release.apk` on both Android phones.
- Go to **Settings → Security** (or Privacy) → enable **Install unknown apps**

### Step 2 — Open BChat on both phones
Enter your codename on each phone and tap **INITIALIZE TERMINAL**.

### Step 3 — Pick roles
- **Phone A** → tap **HOST** → it starts advertising as a BLE peripheral named "BChat"
- **Phone B** → tap **JOIN** → it scans and finds Phone A, connects automatically

### Step 4 — Key exchange (automatic)
Once BLE connects, the app automatically:
1. Exchanges ECDH P-256 public keys
2. Derives a shared AES-256-GCM secret
3. Shows **🔐 E2E** in the top bar

### Step 5 — Verify fingerprint (optional but recommended)
- Tap the **🔐 E2E** badge → your fingerprint appears
- Read it aloud to your peer and confirm they see the same string
- This prevents man-in-the-middle attacks

### Step 6 — Chat
Type and send. All messages are encrypted with AES-256-GCM before transmission.
The lock icon (🔒) on each message confirms encryption.

---

## Device Compatibility

| Device | Requirement | Notes |
|--------|------------|-------|
| Android 6.0+ (API 23+) | ✅ Required | BLE peripheral requires Android 5+ |
| Android 12+ | ✅ Best | New BT permissions fully supported |
| iPhone | ❌ | iOS requires MFi certification for Classic BT; BLE peripheral is limited |
| Laptop (PC) | ❌ | Android app only; use the web version for PCs |

---

## File Structure

```
bchat_flutter/
├── lib/
│   ├── main.dart                    ← Entry point
│   ├── theme.dart                   ← Colors & typography
│   ├── models/
│   │   └── message.dart             ← Message data model
│   ├── services/
│   │   ├── ble_service.dart         ← BLE peripheral + central
│   │   ├── crypto_service.dart      ← ECDH + AES-256-GCM
│   │   └── storage_service.dart     ← SQLite persistence
│   ├── providers/
│   │   └── chat_provider.dart       ← State management + logic
│   └── screens/
│       ├── setup_screen.dart        ← Codename entry
│       ├── role_screen.dart         ← HOST / JOIN selection
│       └── chat_screen.dart         ← Main chat UI
├── android/
│   └── app/
│       ├── src/main/AndroidManifest.xml   ← BT permissions
│       └── build.gradle
└── pubspec.yaml                     ← Dependencies
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "No devices found" | Make sure Phone A is on HOST screen and advertising. Stay within 10m. |
| App crashes on open | Check Bluetooth is ON, location permission granted |
| "Decryption failed" | Both phones must complete key exchange first — tap ⋮ → Send Key Exchange |
| Build fails: SDK not found | Run `flutter doctor` and follow missing steps |
| APK won't install | Enable "Install unknown apps" for your file manager in phone Settings |
| BLE not supported | Device needs Android 5.0+ with BLE hardware (all modern phones have this) |

---

## Security Notes

- Keys are **ephemeral** — regenerated every session, never stored
- Encryption: **AES-256-GCM** — authenticated encryption, prevents tampering
- Key exchange: **ECDH P-256** — forward secrecy per session
- Fingerprint verification protects against MITM
- The BLE layer only carries ciphertext

---

## Extending the App

To add **multi-hop mesh** (3+ devices): use `ble_service.dart` relay pattern —
each device advertises AND scans simultaneously, forwarding packets with TTL.
Android supports concurrent Central + Peripheral roles on most devices.
