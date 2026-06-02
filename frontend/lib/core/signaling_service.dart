import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SignalingService {
  io.Socket? _socket;
  
  // Streams for WebRTC/Chat triggers
  final _connectionController = StreamController<bool>.broadcast();
  final _peerJoinedController = StreamController<Map<String, dynamic>>.broadcast();
  final _peerLeftController = StreamController<String>.broadcast();
  final _signalController = StreamController<Map<String, dynamic>>.broadcast();
  final _relayedMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomDestroyedController = StreamController<String>.broadcast();
  final _peerReconnectedController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get peerJoinedStream => _peerJoinedController.stream;
  Stream<String> get peerLeftStream => _peerLeftController.stream;
  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;
  Stream<Map<String, dynamic>> get relayedMessageStream => _relayedMessageController.stream;
  Stream<String> get roomDestroyedStream => _roomDestroyedController.stream;
  Stream<Map<String, dynamic>> get peerReconnectedStream => _peerReconnectedController.stream;

  bool get isConnected => _socket?.connected ?? false;
  String? get socketId => _socket?.id;

  // Initialize and connect to the Socket.io signaling server
  void connect(String serverUrl) {
    if (_socket != null) {
      _socket!.disconnect();
    }

    print("Connecting to signaling server: $serverUrl");
    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket']) // Force WebSocket only
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      print("Connected to signaling server: ${_socket!.id}");
      _connectionController.add(true);
    });

    _socket!.onDisconnect((_) {
      print("Disconnected from signaling server");
      _connectionController.add(false);
    });

    _socket!.onConnectError((err) {
      print("Signaling connection error: $err");
      _connectionController.add(false);
    });

    // Handle peer joined event
    _socket!.on('peer-joined', (data) {
      print("Signaling event: peer-joined -> $data");
      if (data != null) {
        _peerJoinedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Handle peer left event
    _socket!.on('peer-left', (data) {
      print("Signaling event: peer-left -> $data");
      if (data != null) {
        _peerLeftController.add(data['socketId']?.toString() ?? '');
      }
    });

    // Handle peer reconnected event
    _socket!.on('peer-reconnected', (data) {
      print("Signaling event: peer-reconnected -> $data");
      if (data != null) {
        _peerReconnectedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Handle incoming WebRTC signaling data
    _socket!.on('signal', (data) {
      if (data != null) {
        _signalController.add(Map<String, dynamic>.from(data));
      }
    });

    // Handle incoming relayed encrypted message
    _socket!.on('relayed-message', (data) {
      if (data != null) {
        _relayedMessageController.add(Map<String, dynamic>.from(data));
      }
    });

    // Handle room destroyed event
    _socket!.on('room-destroyed', (data) {
      print("Signaling event: room-destroyed -> $data");
      if (data != null) {
        _roomDestroyedController.add(data['roomId']?.toString() ?? '');
      }
    });

    _socket!.connect();
  }

  // Create a temporary room
  Future<Map<String, dynamic>> createRoom({
    required int roomExpirationMinutes,
    required int messageExpirationMinutes,
    required String x25519PublicKey,
    required String ed25519PublicKey,
    String? signature,
  }) {
    final completer = Completer<Map<String, dynamic>>();

    if (_socket == null || !_socket!.connected) {
      return Future.value({'success': false, 'error': 'Not connected to signaling server'});
    }

    final config = {
      'roomExpirationMinutes': roomExpirationMinutes,
      'messageExpirationMinutes': messageExpirationMinutes,
      'x25519PublicKey': x25519PublicKey,
      'ed25519PublicKey': ed25519PublicKey,
      if (signature != null) 'signature': signature,
    };

    _socket!.emitWithAck('create-room', config, ack: (response) {
      completer.complete(response);
    });

    return completer.future;
  }

  // Join an existing room
  Future<Map<String, dynamic>> joinRoom({
    required String roomId,
    required String x25519PublicKey,
    required String ed25519PublicKey,
    String? signature,
  }) {
    final completer = Completer<Map<String, dynamic>>();

    if (_socket == null || !_socket!.connected) {
      return Future.value({'success': false, 'error': 'Not connected to signaling server'});
    }

    final data = {
      'roomId': roomId.trim().toUpperCase(),
      'x25519PublicKey': x25519PublicKey,
      'ed25519PublicKey': ed25519PublicKey,
      if (signature != null) 'signature': signature,
    };

    _socket!.emitWithAck('join-room', data, ack: (response) {
      completer.complete(response);
    });

    return completer.future;
  }

  // Send a WebRTC signaling message to a target peer
  void sendSignal({
    required String roomId,
    required String targetSocketId,
    required Map<String, dynamic> signalData,
  }) {
    if (_socket == null || !_socket!.connected) return;

    _socket!.emit('signal', {
      'roomId': roomId,
      'targetSocketId': targetSocketId,
      'signalData': signalData,
    });
  }

  // Send message via socket fallback (always encrypted)
  void sendRelayedMessage({
    required String roomId,
    required String encryptedPayload,
  }) {
    if (_socket == null || !_socket!.connected) return;

    _socket!.emit('relay-message', {
      'roomId': roomId,
      'encryptedPayload': encryptedPayload,
    });
  }

  // Trigger explicit destruction of the room
  void destroyRoom(String roomId) {
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('destroy-room', { 'roomId': roomId });
  }

  // Disconnect from signaling server
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  // Dispose stream controllers
  void dispose() {
    _connectionController.close();
    _peerJoinedController.close();
    _peerLeftController.close();
    _signalController.close();
    _relayedMessageController.close();
    _roomDestroyedController.close();
  }
}
