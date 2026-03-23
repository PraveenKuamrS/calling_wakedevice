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
// Persistent storage: name → { fcmToken, ws, online }
const registeredUsers = new Map();
// Active WebSocket connections: wsId → { name, ws }
const activeSockets = new Map();
let wsIdCounter = 0;

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
        registeredUsers.set(name, { 
          fcmToken, 
          ws,
          online: true 
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

      // ── Leave ──────────────────────────────────────────────────
      if (type === "leave") {
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
      userData.online = false;
      userData.ws = null;
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
        online: userData.online || false 
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
  const targetToken = targetData.fcmToken;

  try {
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
    res.status(500).json({ error: err.message });
  }
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