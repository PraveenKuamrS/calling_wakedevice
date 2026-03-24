const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

// ── Firebase Admin ────────────────────────────────────────────────
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const app = express();
app.use(express.json());
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// ── User registry ─────────────────────────────────────────────────
// Persistent storage: name → { fcmToken, ws, online, callState, inCallWith, currentRoom }
const registeredUsers = new Map();
// Active WebSocket connections: wsId → { name, ws }
const activeSockets = new Map();
let wsIdCounter = 0;

// Call states: 'idle' | 'calling' | 'in_call'
// idle: available for calls
// calling: ringing (waiting for answer)
// in_call: currently in an active call

// ── WebSocket ─────────────────────────────────────────────────────
wss.on("connection", (ws) => {
  const wsId = ++wsIdCounter;
  ws.wsId = wsId;
  console.log(`[WS] connected — id: ${wsId}`);

  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data);
      const { type } = msg;

      // ── Register ───────────────────────────────────────────────
      if (type === "register") {
        const { name, fcmToken } = msg;
        if (!name || !fcmToken) return;

        // Mark old socket of same user as inactive
        if (registeredUsers.has(name)) {
          const oldData = registeredUsers.get(name);
          if (oldData.ws && oldData.ws.wsId) {
            activeSockets.delete(oldData.ws.wsId);
          }
        }

        // Store/update user persistently
        const existingUser = registeredUsers.get(name);
        registeredUsers.set(name, { 
          fcmToken, 
          ws,
          online: true,
          callState: existingUser?.callState || 'idle',
          inCallWith: existingUser?.inCallWith || null,
          currentRoom: existingUser?.currentRoom || null
        });
        
        // Track active WebSocket
        activeSockets.set(wsId, { name, ws });
        ws.userName = name;
        
        console.log(`[USER] registered: "${name}" | total: ${registeredUsers.size} | online: ${getOnlineCount()}`);
        ws.send(JSON.stringify({ type: "registered", name }));
        return;
      }

      // ── Join room ──────────────────────────────────────────────
      if (type === "join") {
        const { roomId } = msg;
        ws.roomId = roomId;
        console.log(`[ROOM] "${ws.userName}" joined room: ${roomId}`);

        wss.clients.forEach((client) => {
          if (
            client !== ws &&
            client.readyState === WebSocket.OPEN &&
            client.roomId === roomId
          ) {
            client.send(JSON.stringify({ type: "peer_joined", name: ws.userName }));
          }
        });

        ws.send(JSON.stringify({ type: "joined", roomId }));
        return;
      }

      // ── Relay audio bytes ──────────────────────────────────────
      if (type === "audio") {
        const { roomId, payload } = msg;
        wss.clients.forEach((client) => {
          if (
            client !== ws &&
            client.readyState === WebSocket.OPEN &&
            client.roomId === roomId
          ) {
            client.send(JSON.stringify({ type: "audio", payload }));
          }
        });
        return;
      }
      // ── WebRTC Signaling ───────────────────────────────────
      if (type === "offer" || type === "answer" || type === "ice-candidate") {
        const { target, payload } = msg;
        if (!target) return;
        
        const targetUser = registeredUsers.get(target);
        if (targetUser && targetUser.ws && targetUser.ws.readyState === WebSocket.OPEN) {
          targetUser.ws.send(JSON.stringify({
            type: type,
            from: ws.userName,
            payload: payload
          }));
          console.log(`[SIGNAL] ${type} from "${ws.userName}" → "${target}"`);
        }
        return;
      }

      // ── End call ───────────────────────────────────────────
      if (type === "end-call") {
        const userData = registeredUsers.get(ws.userName);
        if (userData && userData.inCallWith) {
          const peerData = registeredUsers.get(userData.inCallWith);
          if (peerData && peerData.ws && peerData.ws.readyState === WebSocket.OPEN) {
            peerData.ws.send(JSON.stringify({ 
              type: "call-ended",
              reason: "peer_hangup",
              from: ws.userName
            }));
          }
          // Reset both users' call states
          userData.callState = 'idle';
          userData.inCallWith = null;
          userData.currentRoom = null;
          if (peerData) {
            peerData.callState = 'idle';
            peerData.inCallWith = null;
            peerData.currentRoom = null;
          }
          console.log(`[CALL] "${ws.userName}" ended call with "${userData.inCallWith}"`);
        }
        ws.roomId = null;
        return;
      }
      // ── Leave ──────────────────────────────────────────────────
      if (type === "leave") {
        const userData = registeredUsers.get(ws.userName);
        
        // If leaving during a call setup, reset states
        if (userData && userData.callState === 'calling') {
          const peerName = userData.inCallWith;
          
          // Reset caller state
          userData.callState = 'idle';
          userData.inCallWith = null;
          userData.currentRoom = null;
          
          // Reset peer state and notify them
          if (peerName) {
            const peerData = registeredUsers.get(peerName);
            if (peerData) {
              peerData.callState = 'idle';
              peerData.inCallWith = null;
              peerData.currentRoom = null;
              
              // Notify peer that call was cancelled
              if (peerData.ws && peerData.ws.readyState === WebSocket.OPEN) {
                peerData.ws.send(JSON.stringify({ 
                  type: "call_cancelled",
                  from: ws.userName 
                }));
              }
            }
          }
        }
        
        notifyPeerLeft(ws);
        ws.roomId = null;
        return;
      }
    } catch (e) {
      console.error("[WS] parse error:", e.message);
    }
  });

  ws.on("close", () => {
    console.log(`[WS] disconnected — "${ws.userName || wsId}"`);
    if (ws.roomId) notifyPeerLeft(ws);
    
    // Mark user as offline but keep them registered
    if (ws.userName && registeredUsers.has(ws.userName)) {
      const userData = registeredUsers.get(ws.userName);
      
      // Notify peer if user was in a call
      if (userData.inCallWith) {
        const peerData = registeredUsers.get(userData.inCallWith);
        if (peerData && peerData.ws && peerData.ws.readyState === WebSocket.OPEN) {
          peerData.ws.send(JSON.stringify({ 
            type: "call-ended",
            reason: "peer_disconnected",
            from: ws.userName
          }));
          console.log(`[CALL] "${ws.userName}" disconnected, notified "${userData.inCallWith}"`);
          // Reset peer's state
          peerData.callState = 'idle';
          peerData.inCallWith = null;
          peerData.currentRoom = null;
        }
      }
      
      userData.online = false;
      userData.ws = null;
      userData.callState = 'idle';
      userData.inCallWith = null;
      userData.currentRoom = null;
      console.log(`[USER] "${ws.userName}" now offline | online: ${getOnlineCount()}`);
    }
    
    activeSockets.delete(wsId);
  });
});

function notifyPeerLeft(ws) {
  wss.clients.forEach((client) => {
    if (
      client !== ws &&
      client.readyState === WebSocket.OPEN &&
      client.roomId === ws.roomId
    ) {
      client.send(JSON.stringify({ type: "peer_left" }));
    }
  });
}

function getOnlineCount() {
  let count = 0;
  for (const [, userData] of registeredUsers.entries()) {
    if (userData.online) count++;
  }
  return count;
}

// ── GET /users ────────────────────────────────────────────────────
app.get("/users", (req, res) => {
  const me = req.query.me || "";
  const list = [];
  for (const [name, userData] of registeredUsers.entries()) {
    if (name !== me) {
      list.push({ 
        name: name,
        online: userData.online || false,
        callState: userData.callState || 'idle',
        inCall: userData.callState === 'in_call' || userData.callState === 'calling'
      });
    }
  }
  res.json({ users: list });
});

// ── POST /call ────────────────────────────────────────────────────
app.post("/call", async (req, res) => {
  const { callerName, targetName, roomId } = req.body;

  if (!callerName || !targetName || !roomId) {
    return res.status(400).json({ error: "callerName, targetName, roomId required" });
  }

  // Look up target in registered users
  if (!registeredUsers.has(targetName)) {
    return res.status(404).json({ error: `"${targetName}" not registered` });
  }

  const targetData = registeredUsers.get(targetName);
  const callerData = registeredUsers.get(callerName);
  
  // Check if target is already in a call
  if (targetData.callState === 'in_call' || targetData.callState === 'calling') {
    console.log(`[CALL] "${targetName}" is busy (state: ${targetData.callState})`);
    return res.status(409).json({ 
      error: "User is busy",
      busy: true,
      targetState: targetData.callState
    });
  }
  
  // Check if caller is already in a call
  if (callerData && (callerData.callState === 'in_call' || callerData.callState === 'calling')) {
    return res.status(409).json({ 
      error: "You are already in a call",
      busy: true 
    });
  }

  const targetToken = targetData.fcmToken;

  try {
    // Update call states
    targetData.callState = 'calling';
    targetData.inCallWith = callerName;
    targetData.currentRoom = roomId;
    
    if (callerData) {
      callerData.callState = 'calling';
      callerData.inCallWith = targetName;
      callerData.currentRoom = roomId;
    }
    
    const response = await admin.messaging().send({
      token: targetToken,
      data: { type: "incoming_call", callerName, targetName, roomId },
      android: { priority: "high" },
    });
    
    const status = targetData.online ? "online" : "offline";
    console.log(`[FCM] "${callerName}" → "${targetName}" (${status}) | room: ${roomId}`);
    res.json({ success: true, messageId: response, targetOnline: targetData.online });
  } catch (err) {
    console.error("[FCM] error:", err.message);
    // Reset states on error
    targetData.callState = 'idle';
    targetData.inCallWith = null;
    targetData.currentRoom = null;
    if (callerData) {
      callerData.callState = 'idle';
      callerData.inCallWith = null;
      callerData.currentRoom = null;
    }
    res.status(500).json({ error: err.message });
  }
});
    

// ── POST /call-accept ─────────────────────────────────────────────
app.post("/call-accept", (req, res) => {
  const { callerName, targetName } = req.body;
  
  if (!callerName || !targetName) {
    return res.status(400).json({ error: "callerName and targetName required" });
  }
  
  const callerData = registeredUsers.get(callerName);
  const targetData = registeredUsers.get(targetName);
  
  if (callerData && targetData) {
    // Both users are now in call
    callerData.callState = 'in_call';
    targetData.callState = 'in_call';
    console.log(`[CALL] "${targetName}" accepted call from "${callerName}"`);
    res.json({ success: true });
  } else {
    res.status(404).json({ error: "User not found" });
  }
});

// ── POST /call-reject ─────────────────────────────────────────────
app.post("/call-reject", (req, res) => {
  const { callerName, targetName, reason } = req.body;
  
  if (!callerName || !targetName) {
    return res.status(400).json({ error: "callerName and targetName required" });
  }
  
  const callerData = registeredUsers.get(callerName);
  const targetData = registeredUsers.get(targetName);
  
  // Reset states
  if (callerData) {
    callerData.callState = 'idle';
    callerData.inCallWith = null;
    callerData.currentRoom = null;
    
    // Notify caller via WebSocket
    if (callerData.ws && callerData.ws.readyState === WebSocket.OPEN) {
      callerData.ws.send(JSON.stringify({
        type: "call-rejected",
        reason: reason || "declined",
        from: targetName
      }));
    }
  }
  
  if (targetData) {
    targetData.callState = 'idle';
    targetData.inCallWith = null;
    targetData.currentRoom = null;
  }
  
  console.log(`[CALL] "${targetName}" rejected call from "${callerName}" (${reason || 'declined'})`);
  res.json({ success: true });
});

// ── POST /call-cancel ─────────────────────────────────────────────
app.post("/call-cancel", (req, res) => {
  const { callerName, targetName, roomId } = req.body;
  
  if (!callerName || !targetName) {
    return res.status(400).json({ error: "callerName and targetName required" });
  }
  
  const callerData = registeredUsers.get(callerName);
  const targetData = registeredUsers.get(targetName);
  
  // Reset caller state
  if (callerData) {
    callerData.callState = 'idle';
    callerData.inCallWith = null;
    callerData.currentRoom = null;
  }
  
  // Reset target state and notify them
  if (targetData) {
    targetData.callState = 'idle';
    targetData.inCallWith = null;
    targetData.currentRoom = null;
    
    // Notify target via WebSocket that call was cancelled
    if (targetData.ws && targetData.ws.readyState === WebSocket.OPEN) {
      targetData.ws.send(JSON.stringify({
        type: "call_cancelled",
        from: callerName,
        roomId: roomId
      }));
    }
  }
  
  console.log(`[CALL] "${callerName}" cancelled call to "${targetName}"`);
  res.json({ success: true });
});

// ── GET /ping ─────────────────────────────────────────────────────
app.get("/ping", (req, res) =>
  res.json({ 
    status: "ok", 
    totalUsers: registeredUsers.size,
    onlineUsers: getOnlineCount() 
  })
);

// ── Start ─────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server on http://localhost:${PORT}`);
  console.log(`WebSocket on ws://localhost:${PORT}`);
});


// const express = require("express");
// const http = require("http");
// const WebSocket = require("ws");
// const admin = require("firebase-admin");
// const serviceAccount = require("./serviceAccountKey.json");

// // ── Firebase Admin init ──────────────────────────────────────────
// admin.initializeApp({
//   credential: admin.credential.cert(serviceAccount),
// });

// const app = express();
// app.use(express.json());

// const server = http.createServer(app);

// // ── WebSocket server ─────────────────────────────────────────────
// const wss = new WebSocket.Server({ server });

// // rooms: { roomId: [ws1, ws2] }
// const rooms = {};

// wss.on("connection", (ws) => {
//   console.log("[WS] New connection");

//   ws.on("message", (data) => {
//     try {
//       const msg = JSON.parse(data);
//       const { type, roomId, payload } = msg;

//       if (type === "join") {
//         if (!rooms[roomId]) rooms[roomId] = [];
//         rooms[roomId].push(ws);
//         ws.roomId = roomId;
//         console.log(`[WS] joined room: ${roomId} | peers: ${rooms[roomId].length}`);

//         // Tell the joiner how many peers are in the room
//         ws.send(JSON.stringify({ type: "joined", peers: rooms[roomId].length }));

//         // Notify existing peer that someone joined
//         rooms[roomId].forEach((peer) => {
//           if (peer !== ws && peer.readyState === WebSocket.OPEN) {
//             peer.send(JSON.stringify({ type: "peer_joined" }));
//           }
//         });
//       }

//       // Relay signalling messages to the other peer in the room
//       if (["offer", "answer", "ice", "audio"].includes(type)) {
//         const peers = rooms[roomId] || [];
//         peers.forEach((peer) => {
//           if (peer !== ws && peer.readyState === WebSocket.OPEN) {
//             peer.send(JSON.stringify({ type, payload }));
//           }
//         });
//       }

//       if (type === "leave") {
//         cleanupRoom(ws);
//       }
//     } catch (e) {
//       console.error("[WS] bad message", e.message);
//     }
//   });

//   ws.on("close", () => {
//     cleanupRoom(ws);
//     console.log("[WS] disconnected");
//   });
// });

// function cleanupRoom(ws) {
//   const { roomId } = ws;
//   if (!roomId || !rooms[roomId]) return;
//   rooms[roomId] = rooms[roomId].filter((p) => p !== ws);
//   // Notify remaining peer
//   rooms[roomId].forEach((peer) => {
//     if (peer.readyState === WebSocket.OPEN) {
//       peer.send(JSON.stringify({ type: "peer_left" }));
//     }
//   });
//   if (rooms[roomId].length === 0) delete rooms[roomId];
// }

// // ── REST: trigger a call ─────────────────────────────────────────
// // POST /call
// // Body: { targetFcmToken, callerName, roomId }
// app.post("/call", async (req, res) => {
//   const { targetFcmToken, callerName, roomId } = req.body;

//   if (!targetFcmToken || !callerName || !roomId) {
//     return res.status(400).json({ error: "targetFcmToken, callerName, roomId required" });
//   }

//   const message = {
//     token: targetFcmToken,
//     data: {
//       type: "incoming_call",
//       callerName: callerName,
//       roomId: roomId,
//     },
//     android: {
//       priority: "high",
//     },
//   };

//   try {
//     const response = await admin.messaging().send(message);
//     console.log(`[FCM] sent to ${callerName} | room: ${roomId} | msgId: ${response}`);
//     res.json({ success: true, messageId: response });
//   } catch (err) {
//     console.error("[FCM] error:", err.message);
//     res.status(500).json({ error: err.message });
//   }
// });

// // ── Health check ─────────────────────────────────────────────────
// app.get("/ping", (req, res) => res.json({ status: "ok" }));

// // ── Start ─────────────────────────────────────────────────────────
// const PORT = process.env.PORT || 3000;
// server.listen(PORT, () => {
//   console.log(`Server running on http://localhost:${PORT}`);
//   console.log(`WebSocket ready on ws://localhost:${PORT}`);
// });