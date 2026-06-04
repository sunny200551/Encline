import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'encryption_service.dart';
import 'signaling_service.dart';
import 'webrtc_service.dart';
import 'storage_service.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../models/trusted_contact.dart';

enum SessionStatus {
  idle,
  connectingSignaling,
  creatingRoom,
  joiningRoom,
  waitingForPeer,
  negotiatingEncryption,
  handshakeComplete,
  disconnected,
  error
}

class RoomSessionController extends ChangeNotifier {
  final EncryptionService _encryption = EncryptionService();
  final SignalingService _signaling = SignalingService();
  final WebRTCService _webrtc = WebRTCService();
  final StorageService _storage = StorageService();

  // Active state
  Room? activeRoom;
  List<Message> messages = [];
  SessionStatus status = SessionStatus.idle;
  String? errorMessage;
  bool isWebRTCOpen = false;
  String? connectedServerUrl;
  int? latency;

  // Verification state
  bool isPeerVerified = false;
  bool isKeyMismatch = false;
  String? matchedContactName;
  String? expectedEd25519Key;

  // Temporary keypairs for the active session
  SimpleKeyPair? _myX25519KeyPair;
  SimpleKeyPair? _myEd25519KeyPair;

  // Stream subscriptions
  StreamSubscription? _sigConnSub;
  StreamSubscription? _sigPeerJoinedSub;
  StreamSubscription? _sigPeerLeftSub;
  StreamSubscription? _sigSignalSub;
  StreamSubscription? _sigRelaySub;
  StreamSubscription? _sigRoomDestroyedSub;
  StreamSubscription? _sigPeerReconnectedSub;
  StreamSubscription? _sigReconRegSub;

  
  StreamSubscription? _webRTCConnSub;
  StreamSubscription? _webRTCMessageSub;
  StreamSubscription? _webRTCChannelSub;

  RoomSessionController() {
    _setupSignalingStreams();
    _setupWebRTCStreams();
  }

  // Setup listeners for Signaling Service events
  void _setupSignalingStreams() {
    _sigPeerJoinedSub = _signaling.peerJoinedStream.listen((data) async {
      print("Controller: Peer joined signaling -> ${data['socketId']}");
      await _handlePeerJoined(data);
    });

    _sigPeerLeftSub = _signaling.peerLeftStream.listen((peerSocketId) {
      print("Controller: Peer left signaling");
      _addSystemMessage("Peer disconnected from signaling server.");
      isWebRTCOpen = false;
      notifyListeners();
    });

    _sigSignalSub = _signaling.signalStream.listen((data) async {
      final senderSocketId = data['senderSocketId'];
      final signalData = data['signalData'];
      
      if (signalData['type'] == 'offer') {
        // Client receives Host offer
        await _webrtc.handleIncomingSignal(signalData);
        final answer = await _webrtc.createAnswerAndSetLocal();
        _signaling.sendSignal(
          roomId: activeRoom!.id,
          targetSocketId: senderSocketId,
          signalData: answer,
        );
      } else {
        await _webrtc.handleIncomingSignal(signalData);
      }
    });

    _sigRelaySub = _signaling.relayedMessageStream.listen((data) async {
      print("Controller: Received relayed socket message fallback");
      await _handleIncomingEncryptedPayload(data['encryptedPayload']);
    });

    _sigRoomDestroyedSub = _signaling.roomDestroyedStream.listen((roomId) {
      if (activeRoom?.id == roomId) {
        _handleRoomTermination("Room expired or was destroyed by peer.");
      }
    });

    _sigConnSub = _signaling.connectionStream.listen((connected) async {
      if (connected && activeRoom != null) {
        print("Controller: Signaling reconnected. Rejoining room ${activeRoom!.id}...");
        await _rejoinActiveRoom();
      }
    });

    _sigPeerReconnectedSub = _signaling.peerReconnectedStream.listen((data) async {
      print("Controller: Peer reconnected signaling -> ${data['newSocketId']}");
      await _handlePeerReconnected(data);
    });

    _sigReconRegSub = _signaling.reconnectionRegisteredStream.listen((data) async {
      final reconnectCode = data['reconnectCode'];
      print("Controller: Reconnection registered on server -> $reconnectCode");
      _addSystemMessage("Reconnection passcode locked. You can now reconnect using this code.");
      
      if (activeRoom != null && activeRoom!.peerEd25519PublicKeyHex != null) {
        await _storage.updateContactPasscode(activeRoom!.peerEd25519PublicKeyHex!, reconnectCode);
      }
    });
  }


  // Setup listeners for WebRTC events
  void _setupWebRTCStreams() {
    _webRTCMessageSub = _webrtc.messageStream.listen((payload) async {
      print("Controller: Received WebRTC message");
      await _handleIncomingEncryptedPayload(payload);
    });

    _webRTCChannelSub = _webrtc.channelStateStream.listen((state) {
      print("Controller: WebRTC Data Channel state -> $state");
      isWebRTCOpen = (state == RTCDataChannelState.RTCDataChannelOpen);
      if (isWebRTCOpen) {
        _addSystemMessage("Secure WebRTC P2P direct channel established.");
      }
      notifyListeners();
    });
  }

  // 1. Create Room Flow
  Future<void> createRoom({
    required String serverUrl,
    required int roomExpirationMinutes,
    required int messageExpirationMinutes,
    String? customRoomId,
  }) async {
    try {
      connectedServerUrl = serverUrl;
      _updateStatus(SessionStatus.connectingSignaling);
      _signaling.connect(serverUrl);
      
      // Wait for connection
      await _waitForSignalingConnection();
      
      _updateStatus(SessionStatus.creatingRoom);
      
      // Generate temporary keypairs
      _myX25519KeyPair = await _encryption.generateX25519KeyPair();
      _myEd25519KeyPair = await _getOrCreateMyEd25519KeyPair();
      
      final myX25519Hex = await _encryption.getPublicKeyHex(_myX25519KeyPair!);
      final myEd25519Hex = await _encryption.getPublicKeyHex(_myEd25519KeyPair!);
      final signature = await _encryption.signMessage(myX25519Hex, _myEd25519KeyPair!);

      final response = await _signaling.createRoom(
        roomExpirationMinutes: roomExpirationMinutes,
        messageExpirationMinutes: messageExpirationMinutes,
        x25519PublicKey: myX25519Hex,
        ed25519PublicKey: myEd25519Hex,
        signature: signature,
        customRoomId: customRoomId,
      );

      if (response['success'] == true) {
        final roomId = response['roomId'];
        final expirationTime = DateTime.fromMillisecondsSinceEpoch(response['expirationTime']);
        
        final myX25519PrivHex = await _encryption.getPrivateKeyHex(_myX25519KeyPair!);
        final myEd25519PrivHex = await _encryption.getPrivateKeyHex(_myEd25519KeyPair!);

        activeRoom = Room(
          id: roomId,
          expirationTime: expirationTime,
          messageExpirationMinutes: messageExpirationMinutes,
          isHost: true,
          myX25519PublicKeyHex: myX25519Hex,
          myEd25519PublicKeyHex: myEd25519Hex,
          myX25519PrivateKeyHex: myX25519PrivHex,
          myEd25519PrivateKeyHex: myEd25519PrivHex,
        );

        messages = [];
        await _storage.saveRoom(activeRoom!);
        _addSystemMessage("Room $roomId created. Waiting for peer...");
        _updateStatus(SessionStatus.waitingForPeer);
      } else {
        throw Exception(response['error'] ?? 'Signaling server rejected room creation');
      }
    } catch (e) {
      _handleError("Failed to create room: ${e.toString()}");
    }
  }

  // 2. Join Room Flow
  Future<void> joinRoom({
    required String serverUrl,
    required String roomId,
    String? expectedX25519PublicKeyHex, // Verified if parsed from QR/Invite Link
    String? expectedEd25519PublicKeyHex,
  }) async {
    try {
      connectedServerUrl = serverUrl;
      _updateStatus(SessionStatus.connectingSignaling);
      _signaling.connect(serverUrl);
      
      await _waitForSignalingConnection();
      
      _updateStatus(SessionStatus.joiningRoom);
      
      _myX25519KeyPair = await _encryption.generateX25519KeyPair();
      _myEd25519KeyPair = await _getOrCreateMyEd25519KeyPair();
      
      final myX25519Hex = await _encryption.getPublicKeyHex(_myX25519KeyPair!);
      final myEd25519Hex = await _encryption.getPublicKeyHex(_myEd25519KeyPair!);
      final signature = await _encryption.signMessage(myX25519Hex, _myEd25519KeyPair!);

      final response = await _signaling.joinRoom(
        roomId: roomId,
        x25519PublicKey: myX25519Hex,
        ed25519PublicKey: myEd25519Hex,
        signature: signature,
      );

      if (response['success'] == true) {
        final expirationTime = DateTime.fromMillisecondsSinceEpoch(response['expirationTime']);
        final messageExpirationMinutes = response['messageExpirationMinutes'];
        
        final myX25519PrivHex = await _encryption.getPrivateKeyHex(_myX25519KeyPair!);
        final myEd25519PrivHex = await _encryption.getPrivateKeyHex(_myEd25519KeyPair!);

        activeRoom = Room(
          id: roomId,
          expirationTime: expirationTime,
          messageExpirationMinutes: messageExpirationMinutes,
          isHost: false,
          myX25519PublicKeyHex: myX25519Hex,
          myEd25519PublicKeyHex: myEd25519Hex,
          myX25519PrivateKeyHex: myX25519PrivHex,
          myEd25519PrivateKeyHex: myEd25519PrivHex,
        );

        messages = [];
        _addSystemMessage("Joined room $roomId. Performing handshake...");
        _updateStatus(SessionStatus.negotiatingEncryption);

        // Parse host peer details
        final hostPeer = response['peer'];
        if (hostPeer != null) {
          final hostX25519Hex = hostPeer['x25519PublicKey'];
          final hostEd25519Hex = hostPeer['ed25519PublicKey'];
          final hostSignature = hostPeer['signature'];

          // Secure verification: Out-of-band validation if public keys were in the QR/link
          if (expectedX25519PublicKeyHex != null && expectedX25519PublicKeyHex != hostX25519Hex) {
            throw Exception("Security Warning: Man-in-the-middle detected! Host X25519 public key mismatch.");
          }
          if (expectedEd25519PublicKeyHex != null && expectedEd25519PublicKeyHex != hostEd25519Hex) {
            throw Exception("Security Warning: Man-in-the-middle detected! Host Ed25519 public key mismatch.");
          }

          // Verify signature and check trusted contact matching
          await _verifyPeerHandshake(
            peerX25519Hex: hostX25519Hex,
            peerEd25519Hex: hostEd25519Hex,
            peerSignatureHex: hostSignature,
          );

          activeRoom!.peerX25519PublicKeyHex = hostX25519Hex;
          activeRoom!.peerEd25519PublicKeyHex = hostEd25519Hex;

          // Perform ECDH and derive symmetric key
          final sharedSecret = await _encryption.performECDH(_myX25519KeyPair!, hostX25519Hex);
          final derivedKey = await _encryption.deriveSymmetricKey(sharedSecret);
          activeRoom!.symmetricKey = derivedKey;
          
          await _storage.saveRoom(activeRoom!);
          _addSystemMessage("Handshake complete. End-to-end encryption established.");
          _updateStatus(SessionStatus.handshakeComplete);

          // Connect WebRTC
          await _webrtc.initialize(
            roomId: roomId,
            targetSocketId: hostPeer['socketId'],
            signaling: _signaling,
            isHost: false,
          );
        } else {
          throw Exception("Joined room but host was missing");
        }
      } else {
        throw Exception(response['error'] ?? 'Signaling server rejected room join');
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }

  // E2EE Socket Session Reconnection Recovery
  Future<void> _rejoinActiveRoom() async {
    if (activeRoom == null) return;
    try {
      final myX25519Hex = activeRoom!.myX25519PublicKeyHex;
      final myEd25519Hex = activeRoom!.myEd25519PublicKeyHex;

      if (_myEd25519KeyPair == null) {
        print("Controller: Ed25519 KeyPair missing, skipping socket rejoin registration.");
        return;
      }

      final signature = await _encryption.signMessage(myX25519Hex, _myEd25519KeyPair!);

      final response = await _signaling.joinRoom(
        roomId: activeRoom!.id,
        x25519PublicKey: myX25519Hex,
        ed25519PublicKey: myEd25519Hex,
        signature: signature,
      );

      if (response['success'] == true) {
        print("Controller: Rejoined room ${activeRoom!.id} successfully.");
        
        final peer = response['peer'];
        if (peer != null) {
          final peerSocketId = peer['socketId'];
          final peerX25519Hex = peer['x25519PublicKey'];
          final peerEd25519Hex = peer['ed25519PublicKey'];

          activeRoom!.peerX25519PublicKeyHex = peerX25519Hex;
          activeRoom!.peerEd25519PublicKeyHex = peerEd25519Hex;

          // Re-initialize WebRTC connection to peer
          await _webrtc.initialize(
            roomId: activeRoom!.id,
            targetSocketId: peerSocketId,
            signaling: _signaling,
            isHost: activeRoom!.isHost,
          );
        }
      } else {
        print("Controller: Failed to rejoin room: ${response['error']}");
      }
    } catch (e) {
      print("Controller: Error rejoining room: $e");
    }
  }

  // Register reconnection passcode
  Future<Map<String, dynamic>> registerReconnection(String passcode) async {
    if (activeRoom == null) {
      return {'success': false, 'error': 'No active room.'};
    }
    try {
      final deviceId = await _storage.getOrCreateDeviceId();
      final result = await _signaling.registerReconnection(
        roomId: activeRoom!.id,
        reconnectCode: passcode,
        deviceId: deviceId,
      );
      return result;
    } catch (e) {
      print("Controller error registering reconnection: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // Reconnect room using passcode and device ID
  Future<void> reconnectWithPasscode({
    required String serverUrl,
    required String passcode,
    String? expectedEd25519PublicKeyHex,
  }) async {
    try {
      connectedServerUrl = serverUrl;
      _updateStatus(SessionStatus.connectingSignaling);
      _signaling.connect(serverUrl);
      
      await _waitForSignalingConnection();
      
      _updateStatus(SessionStatus.joiningRoom);
      
      _myX25519KeyPair = await _encryption.generateX25519KeyPair();
      _myEd25519KeyPair = await _getOrCreateMyEd25519KeyPair();
      
      final myX25519Hex = await _encryption.getPublicKeyHex(_myX25519KeyPair!);
      final myEd25519Hex = await _encryption.getPublicKeyHex(_myEd25519KeyPair!);
      final signature = await _encryption.signMessage(myX25519Hex, _myEd25519KeyPair!);
      final deviceId = await _storage.getOrCreateDeviceId();

      final response = await _signaling.reconnectRoom(
        reconnectCode: passcode,
        deviceId: deviceId,
        x25519PublicKey: myX25519Hex,
        ed25519PublicKey: myEd25519Hex,
        signature: signature,
      );

      if (response['success'] == true) {
        final expirationTime = DateTime.fromMillisecondsSinceEpoch(response['expirationTime']);
        final messageExpirationMinutes = response['messageExpirationMinutes'];
        
        final myX25519PrivHex = await _encryption.getPrivateKeyHex(_myX25519KeyPair!);
        final myEd25519PrivHex = await _encryption.getPrivateKeyHex(_myEd25519KeyPair!);

        activeRoom = Room(
          id: passcode,
          expirationTime: expirationTime,
          messageExpirationMinutes: messageExpirationMinutes,
          isHost: false, // Defaulting to guest peer logic for E2EE handshake symmetric role
          myX25519PublicKeyHex: myX25519Hex,
          myEd25519PublicKeyHex: myEd25519Hex,
          myX25519PrivateKeyHex: myX25519PrivHex,
          myEd25519PrivateKeyHex: myEd25519PrivHex,
        );

        messages = [];
        _addSystemMessage("Reconnected using passcode. Performing handshake...");
        _updateStatus(SessionStatus.negotiatingEncryption);

        final peer = response['peer'];
        if (peer != null) {
          final peerSocketId = peer['socketId'];
          final peerX25519Hex = peer['x25519PublicKey'];
          final peerEd25519Hex = peer['ed25519PublicKey'];
          final peerSignature = peer['signature'];

          if (expectedEd25519PublicKeyHex != null && expectedEd25519PublicKeyHex != peerEd25519Hex) {
            throw Exception("Security Warning: Man-in-the-middle detected! Peer Ed25519 public key mismatch.");
          }

          await _verifyPeerHandshake(
            peerX25519Hex: peerX25519Hex,
            peerEd25519Hex: peerEd25519Hex,
            peerSignatureHex: peerSignature,
          );

          activeRoom!.peerX25519PublicKeyHex = peerX25519Hex;
          activeRoom!.peerEd25519PublicKeyHex = peerEd25519Hex;

          final sharedSecret = await _encryption.performECDH(_myX25519KeyPair!, peerX25519Hex);
          final derivedKey = await _encryption.deriveSymmetricKey(sharedSecret);
          activeRoom!.symmetricKey = derivedKey;
          
          await _storage.saveRoom(activeRoom!);
          _addSystemMessage("Handshake complete. End-to-end encryption established.");
          _updateStatus(SessionStatus.handshakeComplete);

          await _webrtc.initialize(
            roomId: passcode,
            targetSocketId: peerSocketId,
            signaling: _signaling,
            isHost: false,
          );
        } else {
          // Waiting for host or peer to join
          _addSystemMessage("Waiting for peer to reconnect...");
          _updateStatus(SessionStatus.waitingForPeer);
        }
      } else {
        throw Exception(response['error'] ?? 'Signaling server rejected reconnection');
      }
    } catch (e) {
      _handleError(e.toString());
    }
  }


  // Handle other peer reconnecting and shifting WebRTC socket target
  Future<void> _handlePeerReconnected(Map<String, dynamic> data) async {
    if (activeRoom == null) return;
    
    final newSocketId = data['newSocketId'];
    _addSystemMessage("Peer reconnected. Re-establishing secure channel...");
    
    // Re-initialize WebRTC with the new target socket ID
    await _webrtc.initialize(
      roomId: activeRoom!.id,
      targetSocketId: newSocketId,
      signaling: _signaling,
      isHost: activeRoom!.isHost,
    );
    
    notifyListeners();
  }

  // Handle Host receiving Client details
  Future<void> _handlePeerJoined(Map<String, dynamic> peerInfo) async {
    if (activeRoom == null) return;
    
    try {
      _updateStatus(SessionStatus.negotiatingEncryption);
      
      final peerSocketId = peerInfo['socketId'];
      final peerX25519Hex = peerInfo['x25519PublicKey'];
      final peerEd25519Hex = peerInfo['ed25519PublicKey'];
      final peerSignature = peerInfo['signature'];

      // Verify signature and check trusted contact matching
      await _verifyPeerHandshake(
        peerX25519Hex: peerX25519Hex,
        peerEd25519Hex: peerEd25519Hex,
        peerSignatureHex: peerSignature,
      );

      activeRoom!.peerX25519PublicKeyHex = peerX25519Hex;
      activeRoom!.peerEd25519PublicKeyHex = peerEd25519Hex;

      // Host performs ECDH and derives key
      final sharedSecret = await _encryption.performECDH(_myX25519KeyPair!, peerX25519Hex);
      final derivedKey = await _encryption.deriveSymmetricKey(sharedSecret);
      activeRoom!.symmetricKey = derivedKey;
      
      await _storage.saveRoom(activeRoom!);
      _addSystemMessage("Peer joined room. End-to-end encryption established.");
      _updateStatus(SessionStatus.handshakeComplete);

      // Connect WebRTC
      await _webrtc.initialize(
        roomId: activeRoom!.id,
        targetSocketId: peerSocketId,
        signaling: _signaling,
        isHost: true,
      );
    } catch (e) {
      _handleError("Handshake failure: ${e.toString()}");
    }
  }

  Future<SimpleKeyPair> _getOrCreateMyEd25519KeyPair() async {
    final privHex = await _storage.getMyEd25519PrivateKeyHex();
    final pubHex = await _storage.getMyEd25519PublicKeyHex();
    if (privHex != null && pubHex != null && privHex.isNotEmpty && pubHex.isNotEmpty) {
      try {
        return await _encryption.reconstructEd25519KeyPair(privHex, pubHex);
      } catch (e) {
        print("Error reconstructing saved identity key: $e");
      }
    }
    
    // Generate new persistent identity key
    final keyPair = await _encryption.generateEd25519KeyPair();
    final newPrivHex = await _encryption.getPrivateKeyHex(keyPair);
    final newPubHex = await _encryption.getPublicKeyHex(keyPair);
    await _storage.saveMyEd25519Keys(newPrivHex, newPubHex);
    return keyPair;
  }

  // Cryptographically verify peer signatures and check against trusted pinned contacts
  Future<void> _verifyPeerHandshake({
    required String peerX25519Hex,
    required String peerEd25519Hex,
    required String? peerSignatureHex,
  }) async {
    if (peerSignatureHex == null) {
      isPeerVerified = false;
      _addSystemMessage("Security Warning: Peer signature is missing from handshake!");
      return;
    }

    final verified = await _encryption.verifySignature(
      peerX25519Hex,
      peerSignatureHex,
      peerEd25519Hex,
    );

    isPeerVerified = verified;
    if (!verified) {
      _addSystemMessage("CRITICAL SECURITY ERROR: Handshake signature verification failed!");
      return;
    }

    final contacts = await _storage.getTrustedContacts();
    final matched = contacts.where((c) => c.ed25519PublicKeyHex == peerEd25519Hex).toList();

    if (matched.isNotEmpty) {
      matchedContactName = matched.first.nickname;
      isKeyMismatch = false;
      _addSystemMessage("Identity Verified: Connected to trusted contact '$matchedContactName'.");
    } else {
      matchedContactName = null;
      if (expectedEd25519Key != null && expectedEd25519Key != peerEd25519Hex) {
        isKeyMismatch = true;
        _addSystemMessage("CRITICAL SECURITY WARNING: Pinned identity key mismatch! Eavesdropper or MITM detected!");
      } else {
        isKeyMismatch = false;
        _addSystemMessage("Connected to unverified contact. Save peer as Trusted Contact to secure future chats.");
      }
    }
  }

  Future<void> trustActivePeer(String nickname) async {
    if (activeRoom == null || 
        activeRoom!.peerEd25519PublicKeyHex == null || 
        activeRoom!.peerX25519PublicKeyHex == null) return;
        
    final contact = TrustedContact(
      nickname: nickname,
      x25519PublicKeyHex: activeRoom!.peerX25519PublicKeyHex!,
      ed25519PublicKeyHex: activeRoom!.peerEd25519PublicKeyHex!,
      addedAt: DateTime.now(),
    );
    await _storage.saveTrustedContact(contact);
    matchedContactName = nickname;
    isPeerVerified = true;
    notifyListeners();
  }

  Future<void> removeContact(String ed25519KeyHex) async {
    await _storage.removeTrustedContact(ed25519KeyHex);
    if (activeRoom?.peerEd25519PublicKeyHex == ed25519KeyHex) {
      matchedContactName = null;
      isPeerVerified = false;
    }
    notifyListeners();
  }

  // 3. Messaging Sending
  Future<void> sendMessage(String text) async {
    if (activeRoom == null || activeRoom!.symmetricKey == null) return;

    final messageId = const Uuid().v4();
    final message = Message(
      id: messageId,
      roomId: activeRoom!.id,
      senderId: 'me',
      text: text,
      timestamp: DateTime.now(),
    );

    // Save message locally in history
    messages.add(message);
    await _storage.saveMessage(message);
    notifyListeners();

    // Encrypt payload
    final encryptedPayload = await _encryption.encryptChaCha20Poly1305(
      text, 
      activeRoom!.symmetricKey!,
    );

    // Try sending via WebRTC Data Channel first
    bool sentWebRTC = false;
    if (isWebRTCOpen) {
      sentWebRTC = await _webrtc.sendData(encryptedPayload);
    }

    // Fallback: relay via signaling server if WebRTC failed/closed
    if (!sentWebRTC) {
      print("Controller: WebRTC unavailable, using encrypted socket fallback relay");
      _signaling.sendRelayedMessage(
        roomId: activeRoom!.id,
        encryptedPayload: encryptedPayload,
      );
    }
  }

  // Decrypt and process incoming message payload
  Future<void> _handleIncomingEncryptedPayload(String payload) async {
    if (activeRoom == null || activeRoom!.symmetricKey == null) return;

    try {
      final decryptedText = await _encryption.decryptChaCha20Poly1305(
        payload, 
        activeRoom!.symmetricKey!,
      );

      // Intercept cryptographic silent ping frames
      if (decryptedText.startsWith('__ping__:')) {
        final timestampStr = decryptedText.substring(9);
        await _sendPong(timestampStr);
        return;
      }

      // Intercept cryptographic silent pong frames
      if (decryptedText.startsWith('__pong__:')) {
        final timestampStr = decryptedText.substring(9);
        final sentTimeMs = int.tryParse(timestampStr) ?? 0;
        if (sentTimeMs > 0) {
          latency = DateTime.now().millisecondsSinceEpoch - sentTimeMs;
          notifyListeners();
        }
        return;
      }

      final message = Message(
        id: const Uuid().v4(),
        roomId: activeRoom!.id,
        senderId: 'peer',
        text: decryptedText,
        timestamp: DateTime.now(),
      );

      messages.add(message);
      await _storage.saveMessage(message);
      notifyListeners();
    } catch (e) {
      print("Failed to decrypt incoming packet: $e");
    }
  }

  // Send silent latency check ping frame
  Future<void> sendPing() async {
    if (activeRoom == null || activeRoom!.symmetricKey == null) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await _sendSilentPayload('__ping__:$timestamp');
  }

  // Send silent latency check pong response
  Future<void> _sendPong(String timestampStr) async {
    await _sendSilentPayload('__pong__:$timestampStr');
  }

  // Helper to encrypt and transmit silent frame via WebRTC or socket relay
  Future<void> _sendSilentPayload(String text) async {
    if (activeRoom == null || activeRoom!.symmetricKey == null) return;
    try {
      final encryptedPayload = await _encryption.encryptChaCha20Poly1305(
        text, 
        activeRoom!.symmetricKey!,
      );

      bool sentWebRTC = false;
      if (isWebRTCOpen) {
        sentWebRTC = await _webrtc.sendData(encryptedPayload);
      }

      if (!sentWebRTC) {
        _signaling.sendRelayedMessage(
          roomId: activeRoom!.id,
          encryptedPayload: encryptedPayload,
        );
      }
    } catch (e) {
      print("Controller: Failed to transmit silent frame: $e");
    }
  }

  // Helper to append a system message in the chat feed
  void _addSystemMessage(String text) {
    if (activeRoom == null) return;
    
    final systemMessage = Message(
      id: const Uuid().v4(),
      roomId: activeRoom!.id,
      senderId: 'system',
      text: text,
      timestamp: DateTime.now(),
      isSystem: true,
    );
    messages.add(systemMessage);
    notifyListeners();
  }

  // 4. Room Destruction Flow
  Future<void> destroyActiveRoom() async {
    if (activeRoom == null) return;
    
    print("Explicitly destroying room: ${activeRoom!.id}");
    
    // Notify server to destroy room and disconnect others
    _signaling.destroyRoom(activeRoom!.id);
    
    await _handleRoomTermination("Room permanently shredded and destroyed.");
  }

  // Clean up variables, destroy sockets/WebRTC, wipe messages from device disk
  Future<void> _handleRoomTermination(String reasonMessage) async {
    final roomId = activeRoom?.id;
    
    _webrtc.close();
    _signaling.disconnect();
    isWebRTCOpen = false;
    latency = null;
    
    if (roomId != null) {
      // Secure shred message logs
      await _storage.deleteRoomData(roomId);
    }

    activeRoom = null;
    _myX25519KeyPair = null;
    _myEd25519KeyPair = null;
    isPeerVerified = false;
    isKeyMismatch = false;
    matchedContactName = null;
    expectedEd25519Key = null;
    
    _updateStatus(SessionStatus.disconnected);
    errorMessage = reasonMessage;
    notifyListeners();
  }

  // Pre-warm the server to wake it up early on startup (handling Render cold start)
  Future<void> preWarmServer(String serverUrl) async {
    try {
      print("Pre-warming signaling server at: $serverUrl");
      final uri = Uri.parse("$serverUrl/health");
      final client = http.Client();
      client.get(uri).timeout(const Duration(seconds: 15)).then((_) {
        print("Pre-warm request succeeded, server is active.");
        client.close();
      }).catchError((e) {
        print("Pre-warm request error (expected if booting/slow): $e");
        client.close();
      });
    } catch (e) {
      print("Pre-warm call error: $e");
    }
  }

  // Helper: Waiting for Socket io connection (90 seconds timeout for Render cold starts)
  Future<void> _waitForSignalingConnection() {
    final completer = Completer<void>();
    if (_signaling.isConnected) {
      completer.complete();
      return completer.future;
    }

    StreamSubscription? sub;
    sub = _signaling.connectionStream.listen((connected) {
      if (connected) {
        sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    // Timeout after 90 seconds (generous threshold to survive Render spin-up cold start)
    Future.delayed(const Duration(seconds: 90), () {
      sub?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException("Signaling connection timed out after 90 seconds. The server might be booting up; please try again shortly."));
      }
    });

    return completer.future;
  }

  void _updateStatus(SessionStatus newStatus) {
    status = newStatus;
    notifyListeners();
  }

  void _handleError(String msg) {
    print("Session Controller Error: $msg");
    status = SessionStatus.error;
    errorMessage = msg;
    _webrtc.close();
    _signaling.disconnect();
    isWebRTCOpen = false;
    notifyListeners();
  }

  // Load message logs from disk when user re-opens a recent room
  Future<void> loadRecentRoomMessages(Room room) async {
    activeRoom = room;
    messages = await _storage.getMessages(room.id);
    status = SessionStatus.handshakeComplete; // Since key is loaded from local storage
    
    // Reconstruct keypairs from the saved private keys for session recovery
    if (room.myX25519PrivateKeyHex != null && room.myEd25519PrivateKeyHex != null) {
      print("Controller: Reconstructing session keypairs for room ${room.id}...");
      try {
        _myX25519KeyPair = await _encryption.reconstructX25519KeyPair(
          room.myX25519PrivateKeyHex!,
          room.myX25519PublicKeyHex,
        );
        _myEd25519KeyPair = await _encryption.reconstructEd25519KeyPair(
          room.myEd25519PrivateKeyHex!,
          room.myEd25519PublicKeyHex,
        );
      } catch (e) {
        print("Controller: Error reconstructing keypairs: $e");
      }
    }

    final serverUrl = await _storage.getDefaultServerUrl();
    connectedServerUrl = serverUrl;

    // Connect to signaling server and rejoin room automatically!
    print("Controller: Re-connecting to signaling server to recover session...");
    _signaling.connect(serverUrl);
    
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel stream subscriptions
    _sigConnSub?.cancel();
    _sigPeerJoinedSub?.cancel();
    _sigPeerReconnectedSub?.cancel();
    _sigReconRegSub?.cancel();
    _sigPeerLeftSub?.cancel();
    _sigSignalSub?.cancel();
    _sigRelaySub?.cancel();
    _sigRoomDestroyedSub?.cancel();
    
    _webRTCConnSub?.cancel();
    _webRTCMessageSub?.cancel();
    _webRTCChannelSub?.cancel();

    _signaling.dispose();
    _webrtc.dispose();
    super.dispose();
  }
}
