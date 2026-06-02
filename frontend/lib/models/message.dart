import 'dart:convert';

class Message {
  final String id;
  final String roomId;
  final String senderId; // 'me', 'peer', or 'system'
  final String text;
  final DateTime timestamp;
  final bool isSystem;

  Message({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.isSystem = false,
  });

  bool get isMe => senderId == 'me';
  bool get isPeer => senderId == 'peer';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomId': roomId,
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isSystem': isSystem,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      roomId: map['roomId'],
      senderId: map['senderId'],
      text: map['text'],
      timestamp: DateTime.parse(map['timestamp']),
      isSystem: map['isSystem'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory Message.fromJson(String source) => Message.fromMap(json.decode(source));
}
