const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);

// Serve the compiled Flutter Web client statically
app.use(express.static(path.join(__dirname, '../frontend/build/web')));

const io = new Server(server, {
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
      const { roomExpirationMinutes, messageExpirationMinutes, x25519PublicKey, ed25519PublicKey, signature } = config;
      
      const roomId = generateRoomId();
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
      const { roomId, x25519PublicKey, ed25519PublicKey, signature } = data;
      const room = rooms[roomId];

      if (!room) {
        return callback({ success: false, error: 'Room not found or has expired' });
      }

      if (room.peers.length >= 2) {
        return callback({ success: false, error: 'Room is full (max 2 peers)' });
      }

      // Check if peer is already in room
      const existingPeer = room.peers.find(p => p.socketId === socket.id);
      if (!existingPeer) {
        room.peers.push({
          socketId: socket.id,
          x25519PublicKey,
          ed25519PublicKey,
          signature
        });
      }

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
        // Send existing peer info back to joiner
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
    const { roomId, targetSocketId, signalData } = data;
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
    const { roomId, encryptedPayload } = data;
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
    const { roomId } = data;
    const room = rooms[roomId];
    if (!room) return;

    // Only allow peers inside the room to destroy it
    const isPeer = room.peers.some(p => p.socketId === socket.id);
    if (isPeer) {
      destroyRoom(roomId);
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
        console.log(`Socket ${socket.id} leaving Room ${roomId}`);
        room.peers.splice(peerIndex, 1);
        
        // Notify remaining peer that the connection has been broken
        if (room.peers.length > 0) {
          io.to(room.id).emit('peer-left', { socketId: socket.id });
        } else {
          // If no one is left in the room, destroy it immediately
          destroyRoom(roomId);
        }
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
