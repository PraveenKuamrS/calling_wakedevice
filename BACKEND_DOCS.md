# 📡 Backend Documentation - Call App Server

## What Does the Backend Do?

The backend is a **Node.js server** that enables real-time voice calling between users. It manages user connections, sends call notifications, and relays audio data.

---

## 🔑 Key Technologies

- **Express.js** - HTTP server for REST APIs
- **WebSocket (ws)** - Real-time audio streaming
- **Firebase Admin SDK** - Send push notifications via FCM
- **Firebase Cloud Messaging (FCM)** - Wake up offline users for incoming calls

---

## 🎯 How Backend Uses FCM Tokens

### Simple Flow:

```
1. User opens Flutter app
   ↓
2. App gets FCM token from Firebase
   ↓
3. App sends: Name + FCM Token → Backend via WebSocket
   ↓
4. Backend stores: { name: "Alice", fcmToken: "abc123...", online: true }
   ↓
5. When someone calls Alice:
   - If Alice is online → WebSocket notification
   - If Alice is offline → FCM push notification (wakes up app)
   ↓
6. Alice's phone rings 🔔
```

---

## 📋 Backend Features

### 1️⃣ **User Registration**
- **Endpoint**: WebSocket message `{ type: "register", name, fcmToken }`
- **What it does**: Saves user's name and FCM token in memory
- **Why FCM token**: To send notifications even when app is closed

### 2️⃣ **Get Users List**
- **Endpoint**: `GET /users?me=YourName`
- **Returns**: List of all registered users (except you)
- **Shows**: Online/offline status

### 3️⃣ **Make a Call**
- **Endpoint**: `POST /call`
- **Body**: `{ callerName, targetName, roomId }`
- **What happens**:
  - Finds target user's FCM token
  - Sends Firebase notification with call details
  - Target's phone shows incoming call screen

### 4️⃣ **Real-Time Audio**
- **Via**: WebSocket connection
- **How**: Users join same "room" and audio bytes relay through server
- **Types**: 
  - `join` - Join call room
  - `audio` - Stream voice data
  - `leave` - Exit call

---

## 🔐 FCM Token Lifecycle

| Event | What Happens |
|-------|-------------|
| **App Opens** | Gets fresh FCM token, registers with backend |
| **User Goes Offline** | Backend marks user offline but **keeps FCM token** |
| **Incoming Call** | Backend uses stored FCM token to send notification |
| **App Reopens** | Reconnects WebSocket, updates to online |

---

## 🚀 Running the Backend

```bash
cd Z-call-backend
npm install
node server.js
```

Server starts on: `http://localhost:3000`

---

## 📊 API Summary

| Route | Method | Purpose |
|-------|--------|---------|
| `/ping` | GET | Check server status |
| `/users` | GET | Get all users (with online status) |
| `/call` | POST | Trigger incoming call via FCM |
| WebSocket | WS | Register, join room, stream audio |

---

## 🔔 Why FCM is Important

**Without FCM**: App must always be open to receive calls ❌

**With FCM**: 
- App closed → FCM wakes it up → Shows call screen ✅
- App in background → FCM brings it to front ✅
- Phone locked → FCM shows full-screen call UI ✅

---

## 🗄️ Data Structure

```javascript
registeredUsers = Map {
  "Alice" → { 
    fcmToken: "dKwX...",  // To send notifications
    ws: WebSocket,         // For real-time audio
    online: true           // Current status
  },
  "Bob" → { 
    fcmToken: "fPz9...", 
    ws: null,              // Disconnected
    online: false
  }
}
```

---

## 🎯 Summary

The backend is a **middleman** that:
1. **Stores FCM tokens** from Flutter app
2. **Sends push notifications** when someone gets called
3. **Relays audio** during active calls
4. **Tracks** who's online/offline

**FCM Token = Phone Number** for push notifications 📱
