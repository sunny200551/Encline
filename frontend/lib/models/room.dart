import 'dart:convert';
import 'dart:typed_data';
import '../core/encryption_service.dart';

class Room {
  final String id;
  final DateTime expirationTime;
  final int messageExpirationMinutes;
  final bool isHost;
  
  // Ephemeral keys
  final String myX25519PublicKeyHex;
  final String myEd25519PublicKeyHex;
  
  // Peer keys
  String? peerX25519PublicKeyHex;
  String? peerEd25519PublicKeyHex;
  
  // Ephemeral private keys for session recovery
  String? myX25519PrivateKeyHex;
  String? myEd25519PrivateKeyHex;

  Room({
    required this.id,
    required this.expirationTime,
    required this.messageExpirationMinutes,
    required this.isHost,
    required this.myX25519PublicKeyHex,
    required this.myEd25519PublicKeyHex,
    this.peerX25519PublicKeyHex,
    this.peerEd25519PublicKeyHex,
    this.symmetricKey,
    this.myX25519PrivateKeyHex,
    this.myEd25519PrivateKeyHex,
  });

  bool get isSecure => symmetricKey != null;

  int get remainingSeconds {
    final diff = expirationTime.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  // Convert Room object to Map for storage JSON serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expirationTime': expirationTime.toIso8601String(),
      'messageExpirationMinutes': messageExpirationMinutes,
      'isHost': isHost,
      'myX25519PublicKeyHex': myX25519PublicKeyHex,
      'myEd25519PublicKeyHex': myEd25519PublicKeyHex,
      'peerX25519PublicKeyHex': peerX25519PublicKeyHex,
      'peerEd25519PublicKeyHex': peerEd25519PublicKeyHex,
      'symmetricKeyHex': symmetricKey != null ? EncryptionService.bytesToHex(symmetricKey!) : null,
      'myX25519PrivateKeyHex': myX25519PrivateKeyHex,
      'myEd25519PrivateKeyHex': myEd25519PrivateKeyHex,
    };
  }

  // Create Room object from Map
  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'],
      expirationTime: DateTime.parse(map['expirationTime']),
      messageExpirationMinutes: map['messageExpirationMinutes'],
      isHost: map['isHost'],
      myX25519PublicKeyHex: map['myX25519PublicKeyHex'],
      myEd25519PublicKeyHex: map['myEd25519PublicKeyHex'],
      peerX25519PublicKeyHex: map['peerX25519PublicKeyHex'],
      peerEd25519PublicKeyHex: map['peerEd25519PublicKeyHex'],
      symmetricKey: map['symmetricKeyHex'] != null 
          ? EncryptionService.hexToBytes(map['symmetricKeyHex'])
          : null,
      myX25519PrivateKeyHex: map['myX25519PrivateKeyHex'],
      myEd25519PrivateKeyHex: map['myEd25519PrivateKeyHex'],
    );
  }

  String toJson() => json.encode(toMap());

  factory Room.fromJson(String source) => Room.fromMap(json.decode(source));
}
