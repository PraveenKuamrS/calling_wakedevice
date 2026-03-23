# calling_wakedevice

# 📞 Flutter VoIP Calling App

> WhatsApp-style calling — wakes a killed app, shows native call UI, streams live audio. Built with zero paid SDKs.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter)
![Firebase](https://img.shields.io/badge/Firebase-FCM-FFCA28?style=flat&logo=firebase)
![Node.js](https://img.shields.io/badge/Node.js-Express-339933?style=flat&logo=node.js)
![WebSocket](https://img.shields.io/badge/WebSocket-Audio_Relay-010101?style=flat)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)

---

## 🎯 What this project proves

Most developers assume you need Agora, Zego, or Twilio to build a calling app. This project proves you don't.

**The hard part:** How do you ring someone's phone when your app is completely killed — no background process, no persistent connection, nothing?

**The answer:** FCM high-priority data messages wake Android from a killed state, `flutter_callkit_incoming` renders a native fullscreen call UI, and a simple WebSocket server relays audio between peers in real time.

---

## 🏗️ Architecture

```
Caller Device                    Backend (Node.js)              Callee Device (killed)
─────────────────                ─────────────────              ──────────────────────
Tap user to call  ──POST /call──▶ Look up FCM token
                                  Send FCM push      ──────────▶ Android wakes app
                                                                  CallKit UI appears
                                                                  User accepts call
Join WebSocket room ◀──────────── ws:// relay ──────────────────▶ Join same room
Stream PCM audio  ──────────────────────────────────────────────▶ Play audio
```

---

## ✨ Features

- 🔔 **Wakes killed app** via FCM high-priority data message
- 📱 **Native fullscreen call UI** on lock screen (flutter_callkit_incoming)
- 👥 **Live users list** — see who's online, tap to call
- 🎙️ **Real-time audio** — raw PCM16 mic bytes over WebSocket
- 💾 **Persistent name** — saved with SharedPreferences
- 🆓 **Zero paid SDKs** — no Agora, no Zego, no Twilio

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart) |
| Push wakeup | Firebase FCM V1 API |
| Call UI | flutter_callkit_incoming |
| Backend | Node.js + Express |
| Audio relay | WebSocket (ws package) |
| Mic capture | record package |
| Audio playback | just_audio package |
| Session | SharedPreferences |

---

## 📁 Project Structure

```
├── call-backend/
│   ├── server.js               # Express + WebSocket + FCM
│   ├── package.json
│   └── serviceAccountKey.json  # ← your Firebase key (gitignored)
│
└── call_test/                  # Flutter app
    ├── lib/
    │   └── main.dart           # All screens in one file
    ├── android/
    │   └── app/
    │       └── google-services.json  # ← gitignored
    └── pubspec.yaml
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter 3.x
- Node.js 18+
- Firebase project (free tier is fine)
- Two physical Android devices for testing

---

### 1. Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com) → Create project
2. Add an Android app with your package name
3. Download `google-services.json` → place in `call_test/android/app/`
4. Go to **Project Settings → Service Accounts** → Generate new private key
5. Rename it `serviceAccountKey.json` → place in `call-backend/`

---

### 2. Backend Setup

```bash
cd call-backend
npm install
node server.js
```

Server runs on `http://localhost:3000`

**Verify it works:**
```bash
curl http://localhost:3000/ping
# {"status":"ok","onlineUsers":0}
```

---

### 3. Flutter Setup

Update the server IP in `lib/main.dart`:

```dart
const String SERVER_IP = "YOUR_LOCAL_IP"; // e.g. 192.168.1.10
```

Find your IP:
```bash
# Mac
ifconfig | grep "inet "

# Windows
ipconfig
```

Add dependencies to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  flutter_callkit_incoming: ^2.0.4
  web_socket_channel: ^3.0.1
  permission_handler: ^11.3.1
  http: ^1.2.1
  shared_preferences: ^2.2.3
  record: ^5.1.2
  just_audio: ^0.9.38
```

```bash
flutter pub get
flutter run
```

---

### 4. AndroidManifest.xml Permissions

Add inside `<manifest>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

---

## 🧪 Testing

1. Install the app on **two physical Android devices**
2. Open the app on both — enter a name on each
3. Kill the app on Device B (swipe away from recents)
4. On Device A — tap Device B's name in the users list
5. Watch Device B's screen — fullscreen call UI appears even though app is killed
6. Accept the call → both devices are now in a live audio session

---

## 📡 Backend API

### `GET /ping`
Health check.
```json
{ "status": "ok", "onlineUsers": 2 }
```

### `GET /users?me=YourName`
Returns all online users except yourself.
```json
{ "users": [{ "name": "Alice" }, { "name": "Bob" }] }
```

### `POST /call`
Triggers an FCM push to wake the target device.
```json
{
  "callerName": "Alice",
  "targetName": "Bob",
  "roomId": "room_1234567890"
}
```

### WebSocket Messages

| Type | Direction | Description |
|---|---|---|
| `register` | Client → Server | Register name + FCM token |
| `join` | Client → Server | Join a call room |
| `audio` | Client ↔ Server | Stream PCM audio bytes (base64) |
| `leave` | Client → Server | Leave the room |
| `peer_joined` | Server → Client | Other peer joined the room |
| `peer_left` | Server → Client | Other peer left the room |

---

## ⚠️ Known Limitations

- **Battery optimization** — some Android OEM skins (Xiaomi, Samsung) add aggressive battery management on top of AOSP. Guide users to whitelist the app manually if push delivery is delayed.
- **Audio quality** — raw PCM16 over WebSocket has no noise cancellation, echo suppression, or jitter buffer. For production, upgrade to WebRTC.
- **No encryption** — audio bytes are sent unencrypted. Add E2E encryption before shipping to production.
- **In-memory user registry** — users list is lost on server restart. Add Redis or a database for production.

---

## 🗺️ Roadmap

- [ ] WebRTC upgrade for better audio quality
- [ ] Video calling support
- [ ] End-to-end encryption
- [ ] iOS support (PushKit + CallKit)
- [ ] Persistent user registry with database
- [ ] Call history screen

---

## 🤝 Contributing

PRs are welcome! If you test on a specific Android device and find battery optimization issues, open an issue with the device model and Android version.

---

## 📄 License

MIT — free to use, modify and distribute.

---

## 🙏 Acknowledgements

- [flutter_callkit_incoming](https://pub.dev/packages/flutter_callkit_incoming) — native call UI
- [Firebase FCM](https://firebase.google.com/docs/cloud-messaging) — push wakeup
- [record](https://pub.dev/packages/record) — mic capture
- [just_audio](https://pub.dev/packages/just_audio) — audio playback
