# 🚀 WebRTC Implementation Plan

## 🎯 Goals

1. ✅ Replace raw audio streaming with **WebRTC**
2. ✅ **Instant call disconnect** - When A hangs up, B immediately knows
3. ✅ **Busy state** - Show "User is busy" if already in call
4. ✅ **Better audio quality** - Echo cancellation, noise suppression

---

## 📦 Phase 1: Setup WebRTC (30 mins)

### Backend Changes:
- ✅ Keep existing WebSocket server
- ✅ Add signaling messages: `offer`, `answer`, `ice-candidate`
- ✅ Add user states: `idle`, `calling`, `in_call`, `busy`

### Flutter Changes:
- ✅ Add package: `flutter_webrtc: ^0.9.48`
- ✅ Create WebRTC peer connection
- ✅ Setup audio tracks (microphone)

### Files to Modify:
- `Z-call-backend/server.js` - Add signaling & call states
- `lib/main.dart` - Replace audio streaming with WebRTC

---

## 📦 Phase 2: Signaling Flow (45 mins)

### How WebRTC Signaling Works:

```
Caller (Alice)                Backend               Receiver (Bob)
     │                           │                         │
     │ 1. POST /call             │                         │
     ├──────────────────────────>│                         │
     │                           │ 2. FCM notification     │
     │                           ├────────────────────────>│
     │                           │                         │
     │ 3. createOffer()          │                         │
     │ 4. WS: {type:"offer"}     │                         │
     ├──────────────────────────>│ 5. Forward offer        │
     │                           ├────────────────────────>│
     │                           │                         │
     │                           │ 6. createAnswer()       │
     │                           │ 7. WS: {type:"answer"}  │
     │ 8. Forward answer         │<────────────────────────┤
     │<──────────────────────────┤                         │
     │                           │                         │
     │ 9. ICE candidates (find best network path)         │
     │<═══════════════════════════════════════════════════>│
     │                           │                         │
     │ 10. ✅ Direct audio connection (peer-to-peer!)     │
     │<═══════════════════════════════════════════════════>│
```

### Backend Messages to Add:
```javascript
{type: "offer", target: "Bob", offer: {...}}
{type: "answer", target: "Alice", answer: {...}}
{type: "ice-candidate", target: "Bob", candidate: {...}}
{type: "call-ended", reason: "hangup"}
```

---

## 📦 Phase 3: Call State Management (30 mins)

### User States:
```javascript
registeredUsers.set(name, {
  fcmToken: "...",
  ws: WebSocket,
  online: true,
  callState: "idle" | "calling" | "in_call",  // ← NEW!
  currentRoom: null,
  inCallWith: null  // ← Track who they're talking to
});
```

### State Transitions:
```
idle → (initiates call) → calling → (accepted) → in_call → (hangup) → idle
  ↓
busy ← (receives call while in_call)
```

### Backend Logic:
```javascript
// When someone tries to call
if (targetData.callState === "in_call") {
  return res.status(409).json({ 
    error: "User is busy",
    inCall: true 
  });
}
```

---

## 📦 Phase 4: Instant Call Disconnect (20 mins)

### Current Problem:
- User A hangs up → User B doesn't know immediately

### Solution:
```javascript
// Backend: When user leaves
ws.on("close", () => {
  // Find who they're in call with
  const userData = registeredUsers.get(ws.userName);
  if (userData.inCallWith) {
    const peerData = registeredUsers.get(userData.inCallWith);
    if (peerData.ws) {
      // Immediately notify peer
      peerData.ws.send(JSON.stringify({
        type: "call-ended",
        reason: "peer_disconnected"
      }));
    }
  }
  // Reset state
  userData.callState = "idle";
  userData.inCallWith = null;
});
```

### Flutter:
```dart
// Listen for call-ended
_wsStream.listen((data) {
  final msg = json.decode(data);
  if (msg['type'] == 'call-ended') {
    // Immediately close call screen
    _endCall();
    Navigator.pop(context);
    showSnackBar('Call ended by peer');
  }
});
```

---

## 📦 Phase 5: Enhanced Features (30 mins)

### Features to Add:

1. **Call Duration Timer**
   - Start timer when call connects
   - Show on screen

2. **Network Quality Indicator**
   - WebRTC provides connection stats
   - Show bars: 📶 Excellent / 📶 Good / 📶 Poor

3. **Missed Call Notifications**
   - If user doesn't answer, send FCM: "Missed call from Alice"

4. **Reject Call Reason**
   - User busy / User declined / User offline

---

## 🛠️ Technical Implementation Details

### 1. Backend User Registry Update

```javascript
const registeredUsers = new Map();
// Structure:
{
  name: "Alice",
  fcmToken: "token123",
  ws: WebSocketConnection,
  online: true,
  callState: "idle",           // ← NEW
  currentRoom: null,            // ← NEW
  inCallWith: null,             // ← NEW
  lastSeen: timestamp           // ← NEW
}
```

### 2. Flutter WebRTC Setup

```dart
// Add to pubspec.yaml
dependencies:
  flutter_webrtc: ^0.9.48

// Initialize
RTCPeerConnection? _peerConnection;
MediaStream? _localStream;

Future<void> _createPeerConnection() async {
  final config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},  // Free STUN server
    ]
  };
  
  _peerConnection = await createPeerConnection(config);
  
  // Get microphone
  _localStream = await navigator.mediaDevices.getUserMedia({
    'audio': true,
    'video': false
  });
  
  // Add to peer connection
  _localStream!.getTracks().forEach((track) {
    _peerConnection!.addTrack(track, _localStream!);
  });
}
```

### 3. Signaling Messages

**Backend Addition to `server.js`:**
```javascript
// Relay signaling messages
if (type === "offer" || type === "answer" || type === "ice-candidate") {
  const { target, payload } = msg;
  const targetUser = registeredUsers.get(target);
  
  if (targetUser && targetUser.ws) {
    targetUser.ws.send(JSON.stringify({
      type: type,
      from: ws.userName,
      payload: payload
    }));
  }
}

// Call ended
if (type === "end-call") {
  const userData = registeredUsers.get(ws.userName);
  if (userData.inCallWith) {
    const peerData = registeredUsers.get(userData.inCallWith);
    if (peerData.ws) {
      peerData.ws.send(JSON.stringify({ type: "call-ended" }));
    }
  }
  userData.callState = "idle";
  userData.inCallWith = null;
}
```

---

## 📊 Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    USER A (Caller)                          │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ 1. Tap "Call Bob"
                 ↓
         Check Bob's status (GET /call-status)
                 │
        ┌────────┴────────┐
        │                 │
    [Busy/In Call]    [Available]
        │                 │
   Show "Busy"      2. POST /call
        │                 │
        └─────────────────┴──────> [BACKEND]
                                        │
                                        │ 3. Update state: Bob → "calling"
                                        │ 4. Send FCM to Bob
                                        ↓
                              ┌─────────────────────┐
                              │   USER B (Receiver) │
                              └──────────┬──────────┘
                                         │
                                         │ 5. Phone rings 🔔
                                         │
                                    [Accept/Decline]
                                         │
                            ┌────────────┴───────────┐
                            │                        │
                        [Decline]              [Accept]
                            │                        │
                   Send "call-rejected"    6. Update: Bob → "in_call"
                            │              7. createAnswer()
                            │              8. Send answer via WS
                            ↓                        │
                    Alice gets notified              │
                    "Call declined"                  ↓
                                         9. WebRTC establishes connection
                                         10. AUDIO FLOWS (peer-to-peer)
                                                     │
                                         ┌───────────┴───────────┐
                                         │   IN-CALL SCREEN      │
                                         │  - Mute/Unmute        │
                                         │  - Speaker On/Off     │
                                         │  - Hang Up            │
                                         └───────────┬───────────┘
                                                     │
                                             [Hang Up Click]
                                                     │
                                         11. Send "end-call" to backend
                                         12. Backend notifies peer
                                         13. Both sides disconnect
                                                     │
                                                     ↓
                                         Both users → "idle"
```

---

## 🔥 Key Benefits After Implementation

| Feature | Before | After WebRTC |
|---------|--------|--------------|
| Audio Quality | 📊 Poor | ✅ Crystal Clear |
| Latency | ⏱️ 500-1000ms | ⏱️ 50-150ms |
| Call Disconnect | ❌ Delayed | ✅ Instant |
| Busy Detection | ❌ None | ✅ Works |
| Network Adaptation | ❌ Fixed | ✅ Adaptive |
| Echo/Noise | ❌ Present | ✅ Cancelled |

---

## 🎯 Next Steps (In Order)

### Step 1: Update Backend (Start Here!)
- [ ] Add call state tracking
- [ ] Add signaling message handlers
- [ ] Add busy status check
- [ ] Add instant disconnect logic

### Step 2: Update Flutter App
- [ ] Add `flutter_webrtc` package
- [ ] Create WebRTC manager class
- [ ] Replace audio streaming with WebRTC
- [ ] Handle signaling messages

### Step 3: Testing
- [ ] Test call between 2 devices
- [ ] Test hang up → instant disconnect
- [ ] Test busy state (A calls B, C tries calling B)
- [ ] Test network interruption

### Step 4: Polish
- [ ] Add call timer
- [ ] Add connection quality indicator
- [ ] Add missed call notifications
- [ ] Better UI/UX

---

## 📝 Ready to Start?

**Shall we begin with Step 1: Updating the Backend?**

I'll:
1. Add call state management to `server.js`
2. Add signaling handlers (offer, answer, ICE)
3. Add busy detection
4. Add instant disconnect notification

Then we'll move to Flutter implementation! 🚀
