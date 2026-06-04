const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);

// Serve the compiled Flutter Web client statically
app.use(express.static(path.join(__dirname, '../frontend/build/web')));

// CORS middleware for HTTP endpoints (health check, version checks)
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

const io = new Server(server, {
  pingInterval: 10000,
  pingTimeout: 5000,
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Port configuration
const PORT = process.env.PORT || 3000;

// Memory storage for active rooms
// Format:
// {
//   [roomId]: {
//     id: string,
//     expirationTime: number (timestamp),
//     messageExpirationMinutes: number,
//     peers: [ { socketId: string, x25519PublicKey: string, ed25519PublicKey: string } ],
//     destroyTimeoutId: NodeJS.Timeout
//   }
// }
const rooms = {};

// Memory storage for persistent device pairings and passcodes
const reconnectableRooms = {};
const pendingReconnections = {};


// Helper to generate a unique room ID
function generateRoomId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Avoid easily confused characters (O, 0, I, 1)
  let id;
  do {
    id = '';
    for (let i = 0; i < 6; i++) {
      id += chars.charAt(Math.floor(Math.random() * chars.length));
    }
  } while (rooms[id]);
  return id;
}

// Helper to safely destroy a room
function destroyRoom(roomId) {
  const room = rooms[roomId];
  if (!room) return;

  console.log(`Room ${roomId} is expiring and self-destructing.`);
  
  // Clear the timeout if it exists
  if (room.destroyTimeoutId) {
    clearTimeout(room.destroyTimeoutId);
  }

  // Notify all sockets in the room and disconnect them
  io.to(roomId).emit('room-destroyed', { roomId });
  
  // Find all sockets in room and make them leave
  const sockets = io.sockets.adapter.rooms.get(roomId);
  if (sockets) {
    for (const socketId of sockets) {
      const socket = io.sockets.sockets.get(socketId);
      if (socket) {
        socket.leave(roomId);
      }
    }
  }

  // Remove from memory
  delete rooms[roomId];
}

io.on('connection', (socket) => {
  console.log(`Socket connected: ${socket.id}`);

  // 1. Create Room
  socket.on('create-room', (config, callback) => {
    try {
      const { roomExpirationMinutes, messageExpirationMinutes, x25519PublicKey, ed25519PublicKey, signature, customRoomId } = config;
      
      let roomId;
      if (customRoomId) {
        roomId = customRoomId.trim().toUpperCase();
        const codeRegex = /^[A-Z0-9]{10}$/;
        if (!codeRegex.test(roomId)) {
          return callback({ success: false, error: 'Custom Room ID must be exactly 10 alphanumeric characters.' });
        }
        if (rooms[roomId]) {
          return callback({ success: false, error: 'This code is already active. Please choose another one.' });
        }
      } else {
        roomId = generateRoomId();
      }
      
      const expirationTime = Date.now() + (roomExpirationMinutes * 60 * 1000);
      
      // Schedule room self-destruction
      const destroyTimeoutId = setTimeout(() => {
        destroyRoom(roomId);
      }, roomExpirationMinutes * 60 * 1000);

      rooms[roomId] = {
        id: roomId,
        expirationTime,
        messageExpirationMinutes,
        peers: [
          {
            socketId: socket.id,
            x25519PublicKey,
            ed25519PublicKey,
            signature
          }
        ],
        destroyTimeoutId
      };

      socket.join(roomId);
      console.log(`Room ${roomId} created by socket ${socket.id}. Expires at ${new Date(expirationTime).toISOString()}`);

      callback({
        success: true,
        roomId,
        expirationTime,
        messageExpirationMinutes
      });
    } catch (err) {
      console.error('Error creating room:', err);
      callback({ success: false, error: 'Internal server error during room creation' });
    }
  });

  // 2. Join Room
  socket.on('join-room', (data, callback) => {
    try {
      const { roomId: rawRoomId, x25519PublicKey, ed25519PublicKey, signature } = data;
      const roomId = rawRoomId ? rawRoomId.toUpperCase() : '';
      const room = rooms[roomId];

      if (!room) {
        return callback({ success: false, error: 'Room not found or has expired' });
      }

      // Check if peer is already in room by ed25519 public key (session recovery)
      const existingPeerIndex = room.peers.findIndex(p => p.ed25519PublicKey === ed25519PublicKey);
      if (existingPeerIndex !== -1) {
        const oldSocketId = room.peers[existingPeerIndex].socketId;
        room.peers[existingPeerIndex].socketId = socket.id;
        console.log(`Socket ${socket.id} reconnected to Room ${roomId} (old socket: ${oldSocketId})`);
        
        socket.join(roomId);

        // Notify the other peer in the room about the new socket ID of this peer
        const otherPeer = room.peers.find((p, idx) => idx !== existingPeerIndex);
        if (otherPeer) {
          io.to(otherPeer.socketId).emit('peer-reconnected', {
            oldSocketId,
            newSocketId: socket.id,
            ed25519PublicKey
          });
        }

        return callback({
          success: true,
          roomId,
          expirationTime: room.expirationTime,
          messageExpirationMinutes: room.messageExpirationMinutes,
          peer: otherPeer ? {
            socketId: otherPeer.socketId,
            x25519PublicKey: otherPeer.x25519PublicKey,
            ed25519PublicKey: otherPeer.ed25519PublicKey,
            signature: otherPeer.signature
          } : null
        });
      }

      if (room.peers.length >= 2) {
        return callback({ success: false, error: 'Room is full (max 2 peers)' });
      }

      // New peer joining
      room.peers.push({
        socketId: socket.id,
        x25519PublicKey,
        ed25519PublicKey,
        signature
      });

      socket.join(roomId);
      console.log(`Socket ${socket.id} joined Room ${roomId}`);

      // Notify the other peer in the room about the new joiner and send their keys
      const otherPeer = room.peers.find(p => p.socketId !== socket.id);
      if (otherPeer) {
        // Send joiner's key and signature to the host
        io.to(otherPeer.socketId).emit('peer-joined', {
          socketId: socket.id,
          x25519PublicKey,
          ed25519PublicKey,
          signature
        });
      }

      callback({
        success: true,
        roomId,
        expirationTime: room.expirationTime,
        messageExpirationMinutes: room.messageExpirationMinutes,
        peer: otherPeer ? {
          socketId: otherPeer.socketId,
          x25519PublicKey: otherPeer.x25519PublicKey,
          ed25519PublicKey: otherPeer.ed25519PublicKey,
          signature: otherPeer.signature
        } : null
      });
    } catch (err) {
      console.error('Error joining room:', err);
      callback({ success: false, error: 'Internal server error during join' });
    }
  });

  // 3. WebRTC Signal Relay
  socket.on('signal', (data) => {
    const { roomId: rawRoomId, targetSocketId, signalData } = data;
    const roomId = rawRoomId ? rawRoomId.toUpperCase() : '';
    const room = rooms[roomId];

    if (!room) return;

    // Verify target is still connected in this room
    const targetPeer = room.peers.find(p => p.socketId === targetSocketId);
    if (targetPeer) {
      io.to(targetSocketId).emit('signal', {
        senderSocketId: socket.id,
        signalData
      });
    }
  });

  // 4. Relay Encrypted Message (Fallback if WebRTC data channel fails/NAT block)
  socket.on('relay-message', (data) => {
    const { roomId: rawRoomId, encryptedPayload } = data;
    const roomId = rawRoomId ? rawRoomId.toUpperCase() : '';
    const room = rooms[roomId];
    if (!room) return;

    // Send to other socket in the room
    const otherPeer = room.peers.find(p => p.socketId !== socket.id);
    if (otherPeer) {
      io.to(otherPeer.socketId).emit('relayed-message', {
        senderSocketId: socket.id,
        encryptedPayload
      });
    }
  });

  // 5. Explicit Destroy Room
  socket.on('destroy-room', (data) => {
    const { roomId: rawRoomId } = data;
    const roomId = rawRoomId ? rawRoomId.toUpperCase() : '';
    const room = rooms[roomId];
    if (!room) return;

    // Only allow peers inside the room to destroy it
    const isPeer = room.peers.some(p => p.socketId === socket.id);
    if (isPeer) {
      destroyRoom(roomId);
    }
  });

  // 7. Register Reconnection Passcode
  // Expected input: { roomId, reconnectCode, deviceId }
  socket.on('register-reconnection', (data, callback) => {
    try {
      const { roomId: rawRoomId, reconnectCode: rawReconnectCode, deviceId } = data;
      const roomId = rawRoomId ? rawRoomId.toUpperCase() : '';
      const reconnectCode = rawReconnectCode ? rawReconnectCode.trim() : '';

      if (!roomId || !reconnectCode || !deviceId) {
        return callback({ success: false, error: 'Missing required parameters.' });
      }

      const room = rooms[roomId];
      if (!room) {
        return callback({ success: false, error: 'Active room not found.' });
      }

      // Verify the socket is in this room
      const peer = room.peers.find(p => p.socketId === socket.id);
      if (!peer) {
        return callback({ success: false, error: 'Unauthorized: You are not a peer in this room.' });
      }

      // Initialize pending registrations for this reconnectCode
      if (!pendingReconnections[reconnectCode]) {
        pendingReconnections[reconnectCode] = {
          roomId,
          peers: []
        };
      }

      const pending = pendingReconnections[reconnectCode];
      
      // Prevent duplicate device registration for the same code
      if (!pending.peers.some(p => p.deviceId === deviceId)) {
        pending.peers.push({
          deviceId,
          socketId: socket.id,
          ed25519PublicKey: peer.ed25519PublicKey,
          x25519PublicKey: peer.x25519PublicKey
        });
      }

      console.log(`Device ${deviceId} registered reconnection code '${reconnectCode}' for room ${roomId}`);

      // When both peers have registered, finalize the reconnectable room
      if (pending.peers.length >= 2) {
        reconnectableRooms[reconnectCode] = {
          code: reconnectCode,
          peers: pending.peers.map(p => ({
            deviceId: p.deviceId,
            ed25519PublicKey: p.ed25519PublicKey,
            x25519PublicKey: p.x25519PublicKey
          }))
        };
        
        // Notify both sockets in the active room that reconnection is locked
        io.to(roomId).emit('reconnection-registered', { reconnectCode });
        
        // Clean up pending
        delete pendingReconnections[reconnectCode];
        
        console.log(`Reconnection passcode '${reconnectCode}' successfully locked for 2 devices.`);
      }

      callback({ success: true });
    } catch (err) {
      console.error('Error registering reconnection:', err);
      callback({ success: false, error: 'Internal server error.' });
    }
  });

  // 8. Reconnect via Passcode
  // Expected input: { reconnectCode, deviceId, x25519PublicKey, ed25519PublicKey, signature }
  socket.on('reconnect-room', (data, callback) => {
    try {
      const { reconnectCode: rawReconnectCode, deviceId, x25519PublicKey, ed25519PublicKey, signature } = data;
      const reconnectCode = rawReconnectCode ? rawReconnectCode.trim() : '';

      if (!reconnectCode || !deviceId || !x25519PublicKey || !ed25519PublicKey || !signature) {
        return callback({ success: false, error: 'Missing required parameters.' });
      }

      const savedRoom = reconnectableRooms[reconnectCode];
      if (!savedRoom) {
        return callback({ success: false, error: 'Reconnection passcode not found or expired.' });
      }

      // Verify deviceId is authorized for this reconnectCode
      const registeredPeer = savedRoom.peers.find(p => p.deviceId === deviceId);
      if (!registeredPeer) {
        return callback({ success: false, error: 'Unauthorized: This device is not registered to use this passcode.' });
      }

      // Verify that the connecting ed25519PublicKey matches the registered one
      if (registeredPeer.ed25519PublicKey !== ed25519PublicKey) {
        return callback({ success: false, error: 'Security alert: Identity key mismatch for this device.' });
      }

      // Find or create active temporary room mapped to this reconnectCode
      let room = rooms[reconnectCode];
      if (!room) {
        // Create a new temporary room using the reconnectCode as the roomId
        const roomExpirationMinutes = 30; // Default expiration for reconnection sessions
        const expirationTime = Date.now() + (roomExpirationMinutes * 60 * 1000);
        
        const destroyTimeoutId = setTimeout(() => {
          destroyRoom(reconnectCode);
        }, roomExpirationMinutes * 60 * 1000);

        room = {
          id: reconnectCode,
          expirationTime,
          messageExpirationMinutes: 10, // Default message expiration
          peers: [],
          destroyTimeoutId
        };
        rooms[reconnectCode] = room;
        console.log(`Temporary Room ${reconnectCode} recreated for reconnection.`);
      }

      // Check if peer is already registered in the active room (session recovery)
      const existingPeerIndex = room.peers.findIndex(p => p.ed25519PublicKey === ed25519PublicKey);
      if (existingPeerIndex !== -1) {
        const oldSocketId = room.peers[existingPeerIndex].socketId;
        room.peers[existingPeerIndex].socketId = socket.id;
        
        socket.join(reconnectCode);
        console.log(`Socket ${socket.id} (device ${deviceId}) re-joined active reconnection room ${reconnectCode}`);

        const otherPeer = room.peers.find((p, idx) => idx !== existingPeerIndex);
        if (otherPeer) {
          io.to(otherPeer.socketId).emit('peer-reconnected', {
            oldSocketId,
            newSocketId: socket.id,
            ed25519PublicKey
          });
        }

        return callback({
          success: true,
          roomId: reconnectCode,
          expirationTime: room.expirationTime,
          messageExpirationMinutes: room.messageExpirationMinutes,
          peer: otherPeer ? {
            socketId: otherPeer.socketId,
            x25519PublicKey: otherPeer.x25519PublicKey,
            ed25519PublicKey: otherPeer.ed25519PublicKey,
            signature: otherPeer.signature
          } : null
        });
      }

      if (room.peers.length >= 2) {
        return callback({ success: false, error: 'Reconnection room is already full.' });
      }

      // Add to peers list
      room.peers.push({
        socketId: socket.id,
        x25519PublicKey,
        ed25519PublicKey,
        signature
      });

      socket.join(reconnectCode);
      console.log(`Socket ${socket.id} (device ${deviceId}) joined reconnection room ${reconnectCode}`);

      // Notify other peer if present
      const otherPeer = room.peers.find(p => p.socketId !== socket.id);
      if (otherPeer) {
        io.to(otherPeer.socketId).emit('peer-joined', {
          socketId: socket.id,
          x25519PublicKey,
          ed25519PublicKey,
          signature
        });
      }

      callback({
        success: true,
        roomId: reconnectCode,
        expirationTime: room.expirationTime,
        messageExpirationMinutes: room.messageExpirationMinutes,
        peer: otherPeer ? {
          socketId: otherPeer.socketId,
          x25519PublicKey: otherPeer.x25519PublicKey,
          ed25519PublicKey: otherPeer.ed25519PublicKey,
          signature: otherPeer.signature
        } : null
      });

    } catch (err) {
      console.error('Error in reconnect-room:', err);
      callback({ success: false, error: 'Internal server error.' });
    }
  });


  // 6. Disconnect
  socket.on('disconnect', () => {
    console.log(`Socket disconnected: ${socket.id}`);
    
    // Find rooms containing this socket
    for (const roomId in rooms) {
      const room = rooms[roomId];
      const peerIndex = room.peers.findIndex(p => p.socketId === socket.id);
      
      if (peerIndex !== -1) {
        console.log(`Socket ${socket.id} (peer in Room ${roomId}) disconnected.`);
        // Notify remaining peer that the connection has been broken
        const otherPeer = room.peers.find(p => p.socketId !== socket.id);
        if (otherPeer) {
          io.to(otherPeer.socketId).emit('peer-left', { socketId: socket.id });
        }
        // Note: We do NOT remove the peer or destroy the room immediately.
        // The room will self-destruct naturally at expirationTime.
      }
    }
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', activeRoomsCount: Object.keys(rooms).length });
});

// App update endpoints
app.get('/version', (req, res) => {
  res.json({
    version: '1.0.1',
    notes: 'E2EE signaling connectivity and Web invite link routing updates.',
    apkUrl: '/download-apk'
  });
});

app.get('/download-apk', (req, res) => {
  const apkPath = path.resolve(__dirname, '../frontend/build/app/outputs/flutter-apk/app-release.apk');
  res.sendFile(apkPath, (err) => {
    if (err) {
      res.status(404).send('APK has not been compiled on the server yet.');
    }
  });
});

server.listen(PORT, () => {
  console.log(`Signaling server listening on port ${PORT}`);
});
