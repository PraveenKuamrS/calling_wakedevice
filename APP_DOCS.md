# 📱 Flutter App Documentation - Call App

## What Does the App Do?

A **real-time voice calling app** built with Flutter. Users can call each other even when the app is closed, thanks to Firebase Cloud Messaging (FCM).

---

## 🔧 Key Technologies

- **Flutter** - Cross-platform mobile app
- **Firebase Messaging** - Receive push notifications
- **CallKit** - Native calling UI (shows like phone call)
- **WebSocket** - Real-time audio streaming
- **Record & FlutterSound** - Record and play voice

---

## 🎯 How App Uses FCM Token

### Simple 5-Step Flow:

```
Step 1: App starts → Gets FCM token from Firebase
        Token looks like: "dKwX7f8p..." (unique to this phone)

Step 2: User enters name → App sends to backend:
        {
          type: "register",
          name: "Alice",
          fcmToken: "dKwX7f8p..."
        }

Step 3: Backend saves: Alice = this FCM token

Step 4: Bob wants to call Alice → Backend finds Alice's FCM token

Step 5: Backend sends notification to Alice's token →
        Alice's phone rings! 🔔
```

---

## 📲 App Screens

### 1️⃣ **Name Screen**
- Enter your name (first time only)
- Name saved in local storage
- Moves to Users Screen

### 2️⃣ **Users Screen**
- Shows all registered users
- 🟢 Green = Online | ⚪ Gray = Offline
- Tap user → Make call

### 3️⃣ **Call Screen**
- Voice recording and playback
- Real-time audio streaming
- Hang up button

---

## 🔥 Firebase Setup Flow

```dart
// 1. Initialize Firebase
await Firebase.initializeApp();

// 2. Request notification permission
await FirebaseMessaging.instance.requestPermission();

// 3. Get FCM token
String? fcmToken = await FirebaseMessaging.instance.getToken();
// fcmToken = "dKwX7f8p..." ← Unique device ID

// 4. Send to backend
_ws.sink.add(json.encode({
  'type': 'register',
  'name': userName,
  'fcmToken': fcmToken  // ← Backend saves this!
}));
```

---

## 📞 Call Flow

### **Scenario A: Calling Someone**

```
1. Tap "Bob" in users list
   ↓
2. App creates room ID: timestamp_Alice_Bob
   ↓
3. App sends to backend: POST /call
   {
     callerName: "Alice",
     targetName: "Bob",
     roomId: "1234567890_Alice_Bob"
   }
   ↓
4. Backend finds Bob's FCM token
   ↓
5. Firebase sends notification to Bob's phone
   ↓
6. Bob's phone shows incoming call UI
   ↓
7. Bob accepts → Both join same room
   ↓
8. Audio streams via WebSocket
```

### **Scenario B: Receiving a Call**

```
1. FCM notification arrives
   ↓
2. Data: { type: "incoming_call", callerName: "Alice", roomId: "..." }
   ↓
3. App shows CallKit UI (looks like native phone call)
   ↓
4. User taps "Accept" → Navigate to Call Screen
   ↓
5. Connect to WebSocket room
   ↓
6. Start recording → Stream audio to caller
```

---

## 🔔 FCM Message Handling

### **When App is Open (Foreground)**
```dart
FirebaseMessaging.onMessage.listen((message) {
  // Show incoming call screen immediately
  _showIncomingCallUI(
    callerName: message.data['callerName'],
    roomId: message.data['roomId']
  );
});
```

### **When App is Closed (Background)**
```dart
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
  RemoteMessage message
) async {
  // Wake up app, show call screen
  await _showIncomingCallUI(...);
}
```

---

## 🎙️ Audio Streaming

### Recording Audio
```dart
final recorder = AudioRecorder();
await recorder.start(); // Start recording

// Send audio bytes to backend every 100ms
Timer.periodic(Duration(milliseconds: 100), (_) async {
  final bytes = await recorder.getBytes();
  _ws.sink.add(json.encode({
    'type': 'audio',
    'roomId': currentRoom,
    'payload': base64Encode(bytes)
  }));
});
```

### Playing Received Audio
```dart
// When audio data arrives from WebSocket
_ws.stream.listen((data) {
  final msg = json.decode(data);
  if (msg['type'] == 'audio') {
    final bytes = base64Decode(msg['payload']);
    await _player.playBytes(bytes); // Play audio
  }
});
```

---

## 🔐 Permissions Required

- ✅ **Microphone** - Record voice
- ✅ **Notifications** - Show incoming calls

```dart
await Permission.microphone.request();
await Permission.notification.request();
```

---

## 📁 Project Structure

```
lib/
├── main.dart              # Main app entry point
    ├── NameScreen         # Enter username
    ├── UsersScreen        # List of users  
    └── CallScreen         # Active call UI
```

---

## 🔗 Connection to Backend

```dart
// Server configuration
const SERVER_IP = "192.168.1.177";   // Change to your IP
const SERVER_URL = "http://$SERVER_IP:3000";
const WS_URL = "ws://$SERVER_IP:3000";

// WebSocket connection
final channel = WebSocketChannel.connect(Uri.parse(WS_URL));
```

---

## 🎯 Why FCM Token is Critical

| Scenario | Without FCM Token | With FCM Token |
|----------|-------------------|----------------|
| **App is closed** | ❌ Call missed | ✅ Phone rings |
| **App in background** | ❌ No notification | ✅ Full screen call |
| **Phone locked** | ❌ Silent | ✅ Call screen shows |
| **No internet briefly** | ❌ Lost | ✅ Queued notification |

**FCM Token = Your permanent address for notifications** 📬

---

## 🚀 Running the App

1. **Start backend first**:
   ```bash
   cd Z-call-backend
   npm install
   node server.js
   ```

2. **Update server IP** in `main.dart`:
   ```dart
   const SERVER_IP = "YOUR_COMPUTER_IP"; // Find with ipconfig/ifconfig
   ```

3. **Add google-services.json** (from Firebase Console)
   - Place in: `android/app/google-services.json`

4. **Run app**:
   ```bash
   flutter pub get
   flutter run
   ```

---

## 📊 Complete Call Journey

```
┌─────────────┐                                    ┌─────────────┐
│   Alice     │                                    │     Bob     │
│  (Caller)   │                                    │  (Receiver) │
└──────┬──────┘                                    └──────┬──────┘
       │                                                  │
       │ 1. Opens app → Gets FCM token                   │
       │ 2. Registers: "Alice" + token                   │
       │            ↓                                     │
       │      ┌──────────┐                               │
       │ ──→  │ Backend  │  ←────────────────────────── │
       │      └──────────┘                               │
       │         Stores:                                 │
       │         Alice → token_A                         │
       │         Bob → token_B                           │
       │                                                 │
       │ 3. Taps "Call Bob"                              │
       │ 4. POST /call → Backend                         │
       │            ↓                                    │
       │      Backend finds Bob's FCM token (token_B)    │
       │            ↓                                    │
       │      Sends FCM push notification                │
       │            ↓                                    │
       │                                   5. 📱 Phone rings!
       │                                   6. Bob accepts
       │            ↓                                    │
       │   Both join WebSocket room "1234_Alice_Bob"    │
       │ ←──────────────────────────────────────────→   │
       │          7. Real-time audio streaming           │
       │              (via WebSocket)                    │
       └─────────────────────────────────────────────────┘
```

---

## 💡 Key Takeaways

1. **FCM Token** = Unique identifier for push notifications
2. **Backend stores FCM tokens** so it knows where to send call alerts
3. **CallKit** makes calls look native (like regular phone calls)
4. **WebSocket** handles real-time audio during active calls
5. **Works even when app is closed** thanks to FCM background handler

---

## 🔧 Configuration Checklist

- [ ] Firebase project created
- [ ] `google-services.json` added to Android folder
- [ ] Permissions granted (Microphone, Notifications)
- [ ] Server IP updated in code
- [ ] Backend running on port 3000
- [ ] Both devices on same network (or use public server)

---

## 🎉 That's It!

Your Flutter app now supports **real-time voice calling** with **push notifications** powered by FCM tokens! 🚀
