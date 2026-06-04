import 'dart:convert';

class TrustedContact {
  final String nickname;
  final String x25519PublicKeyHex;
  final String ed25519PublicKeyHex;
  final DateTime addedAt;
  final String? reconnectPasscode;

  TrustedContact({
    required this.nickname,
    required this.x25519PublicKeyHex,
    required this.ed25519PublicKeyHex,
    required this.addedAt,
    this.reconnectPasscode,
  });

  Map<String, dynamic> toMap() {
    return {
      'nickname': nickname,
      'x25519PublicKeyHex': x25519PublicKeyHex,
      'ed25519PublicKeyHex': ed25519PublicKeyHex,
      'addedAt': addedAt.toIso8601String(),
      'reconnectPasscode': reconnectPasscode,
    };
  }

  factory TrustedContact.fromMap(Map<String, dynamic> map) {
    return TrustedContact(
      nickname: map['nickname'] ?? '',
      x25519PublicKeyHex: map['x25519PublicKeyHex'] ?? '',
      ed25519PublicKeyHex: map['ed25519PublicKeyHex'] ?? '',
      addedAt: map['addedAt'] != null 
          ? DateTime.parse(map['addedAt']) 
          : DateTime.now(),
      reconnectPasscode: map['reconnectPasscode'],
    );
  }

  String toJson() => json.encode(toMap());

  factory TrustedContact.fromJson(String source) => 
      TrustedContact.fromMap(json.decode(source));
}
