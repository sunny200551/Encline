import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final List<RTCIceCandidate> _queuedCandidates = [];
  
  final _connectionStateController = StreamController<RTCPeerConnectionState>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  final _channelStateController = StreamController<RTCDataChannelState>.broadcast();

  Stream<RTCPeerConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<RTCDataChannelState> get channelStateStream => _channelStateController.stream;

  bool get isDataChannelOpen => _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;

  final Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };

  // Initialize the peer connection and set up signaling listeners
  Future<void> initialize({
    required String roomId,
    required String targetSocketId,
    required SignalingService signaling,
    required bool isHost,
  }) async {
    await close(); // Clean up existing connection

    print("Initializing WebRTC Peer Connection (isHost: $isHost)");
    _peerConnection = await createPeerConnection(_config, _constraints);

    // 1. ICE Candidate Gathering
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        print("WebRTC: Local ICE candidate generated");
        signaling.sendSignal(
          roomId: roomId,
          targetSocketId: targetSocketId,
          signalData: {
            'type': 'candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      }
    };

    // 2. Connection State Listeners
    _peerConnection!.onConnectionState = (state) {
      print("WebRTC: Connection state changed -> $state");
      _connectionStateController.add(state);
    };

    // 3. Handle Data Channel establishment
    if (isHost) {
      // Host creates the data channel
      print("WebRTC Host: Creating Data Channel 'chat'");
      final init = RTCDataChannelInit()..ordered = true;
      _dataChannel = await _peerConnection!.createDataChannel('chat', init);
      _setupDataChannelListeners();
      
      // Generate and send Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      
      print("WebRTC Host: Sending Offer");
      signaling.sendSignal(
        roomId: roomId,
        targetSocketId: targetSocketId,
        signalData: {
          'type': 'offer',
          'sdp': offer.sdp,
        },
      );
    } else {
      // Client waits for the Host's data channel to be passed
      _peerConnection!.onDataChannel = (channel) {
        print("WebRTC Client: Received remote Data Channel");
        _dataChannel = channel;
        _setupDataChannelListeners();
      };
    }
  }

  // Set up listeners for the data channel (open, closed, message)
  void _setupDataChannelListeners() {
    if (_dataChannel == null) return;

    _dataChannel!.onDataChannelState = (state) {
      print("WebRTC DataChannel: State changed -> $state");
      _channelStateController.add(state);
    };

    _dataChannel!.onMessage = (message) {
      print("WebRTC DataChannel: Raw message received");
      if (message.isBinary) {
        // We only expect text messages
        return;
      }
      _messageController.add(message.text);
    };
  }

  // Process queued ICE candidates after remote description is set
  Future<void> _processQueuedCandidates() async {
    print("WebRTC: Processing ${_queuedCandidates.length} queued ICE candidates");
    for (final candidate in _queuedCandidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        print("WebRTC: Error adding queued candidate: $e");
      }
    }
    _queuedCandidates.clear();
  }

  // Handle incoming signaling messages from Socket server
  Future<void> handleIncomingSignal(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;

    final type = data['type'];
    if (type == 'offer') {
      print("WebRTC Client: Handling Offer");
      final sdp = data['sdp'];
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      await _processQueuedCandidates();
    } else if (type == 'answer') {
      print("WebRTC Host: Handling Answer");
      final sdp = data['sdp'];
      await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      await _processQueuedCandidates();
    } else if (type == 'candidate') {
      print("WebRTC: Adding remote ICE Candidate");
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      
      final remoteDesc = await _peerConnection!.getRemoteDescription();
      if (remoteDesc == null) {
        print("WebRTC: Queueing remote ICE candidate (remote description not set yet)");
        _queuedCandidates.add(candidate);
      } else {
        await _peerConnection!.addCandidate(candidate);
      }
    }
  }

  // Send answer descriptor (For client, since we need targetSocketId in the controller)
  Future<Map<String, dynamic>> createAnswerAndSetLocal() async {
    if (_peerConnection == null) throw Exception("Peer connection not initialized");
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    return {
      'type': 'answer',
      'sdp': answer.sdp,
    };
  }

  // Send encrypted text message through the WebRTC data channel
  Future<bool> sendData(String text) async {
    if (_dataChannel == null || _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      print("WebRTC: Cannot send data, channel is not open");
      return false;
    }
    
    await _dataChannel!.send(RTCDataChannelMessage(text));
    return true;
  }

  // Close connections and streams
  Future<void> close() async {
    print("Closing WebRTC Peer Connection and Data Channel");
    _queuedCandidates.clear();
    await _dataChannel?.close();
    _dataChannel = null;
    
    await _peerConnection?.close();
    _peerConnection = null;
  }

  void dispose() {
    _connectionStateController.close();
    _messageController.close();
    _channelStateController.close();
  }
}
