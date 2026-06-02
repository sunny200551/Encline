import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/room_session_controller.dart';
import '../models/message.dart';
import '../widgets/glassmorphic_container.dart';

class ChatScreen extends StatefulWidget {
  final bool isEmbedded;
  const ChatScreen({Key? key, this.isEmbedded = false}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  Timer? _countdownTimer;
  Timer? _msgExpirationTimer;
  String _timeRemainingStr = "00:00";
  bool _showTrustForm = false;

  @override
  void initState() {
    super.initState();
    _startTimers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _startTimers() {
    final controller = Provider.of<RoomSessionController>(context, listen: false);
    final room = controller.activeRoom;
    if (room == null) return;

    // 1. Room self-destruction countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (room.remainingSeconds <= 0) {
        timer.cancel();
      } else {
        final totalSec = room.remainingSeconds;
        final hours = totalSec ~/ 3600;
        final minutes = (totalSec % 3600) ~/ 60;
        final seconds = totalSec % 60;
        
        if (mounted) {
          setState(() {
            if (hours > 0) {
              _timeRemainingStr = "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
            } else {
              _timeRemainingStr = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
            }
          });
        }
      }
    });

    // 2. Message local auto-destruction timer
    if (room.messageExpirationMinutes > 0) {
      _msgExpirationTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _checkMessageExpiration(controller, room.messageExpirationMinutes);
      });
    }
  }

  void _checkMessageExpiration(RoomSessionController controller, int expirationMinutes) async {
    final now = DateTime.now();
    final List<Message> expired = [];

    for (final msg in controller.messages) {
      if (msg.isSystem) continue;
      final diff = now.difference(msg.timestamp).inMinutes;
      if (diff >= expirationMinutes) {
        expired.add(msg);
      }
    }

    if (expired.isNotEmpty && mounted) {
      print("Local message expiration triggered for ${expired.length} messages.");
      setState(() {
        controller.messages.removeWhere((m) => expired.any((e) => e.id == m.id));
      });
      controller.notifyListeners();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final controller = Provider.of<RoomSessionController>(context, listen: false);
    controller.sendMessage(text);
    _messageController.clear();
    
    Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
  }

  Future<void> _destroyRoom() async {
    final controller = Provider.of<RoomSessionController>(context, listen: false);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Destroy Room?"),
        content: const Text("This will permanently shred and delete all messages from this device and notify the peer. This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Shred & Destroy", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await controller.destroyActiveRoom();
      if (!mounted) return;
      if (!widget.isEmbedded) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _saveAsTrusted(RoomSessionController controller) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await controller.trustActivePeer(name);
    setState(() {
      _showTrustForm = false;
      _nameController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Contact '$name' added to Trusted Contacts."),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _msgExpirationTimer?.cancel();
    _messageController.dispose();
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<RoomSessionController>(context);
    final room = controller.activeRoom;

    // If room is terminated, pop back to home if not embedded
    if (room == null && controller.status == SessionStatus.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.errorMessage ?? "Room terminated."),
            backgroundColor: AppColors.warning,
          ),
        );
        if (!widget.isEmbedded) {
          Navigator.of(context).pop();
        }
      });
      return _buildEmptyState();
    }

    if (room == null) {
      return _buildEmptyState();
    }

    final String displayName = controller.matchedContactName ?? "Peer (${room.id})";

    final chatWidget = Container(
      color: const Color(0xFF0b141a), // WhatsApp Dark Background
      child: Column(
        children: [
          // Header Bar
          _buildHeader(displayName, controller),

          // Security Banners
          if (controller.isKeyMismatch) _buildKeyMismatchBanner(),
          if (controller.isPeerVerified && controller.matchedContactName == null) 
            _buildUnverifiedContactBanner(controller),

          // Messages View
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              itemCount: controller.messages.length,
              itemBuilder: (context, index) {
                final msg = controller.messages[index];
                if (msg.isSystem) return _buildSystemBubble(msg.text);
                return _buildChatBubble(msg);
              },
            ),
          ),
          
          // Input field bar
          _buildInputFieldBar(),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return chatWidget;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0b141a),
      body: SafeArea(child: chatWidget),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: const Color(0xFF222e35),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_person_outlined, size: 64, color: Colors.white12),
            SizedBox(height: 16),
            Text(
              "No active secure room",
              style: TextStyle(color: Colors.white30, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String name, RoomSessionController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF202c33), // WhatsApp Header Color
        border: Border(bottom: BorderSide(color: Color(0xFF2f3b43), width: 0.5)),
      ),
      child: Row(
        children: [
          if (!widget.isEmbedded)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
          CircleAvatar(
            backgroundColor: const Color(0xFF00a884).withOpacity(0.15),
            radius: 20,
            child: Icon(
              Icons.person,
              color: controller.isPeerVerified ? const Color(0xFF00a884) : Colors.white54,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                    ),
                    if (controller.isPeerVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, color: Color(0xFF00a884), size: 16),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      controller.isWebRTCOpen ? Icons.shield : Icons.lock_outline,
                      color: controller.isWebRTCOpen ? const Color(0xFF00a884) : Colors.white38,
                      size: 11,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      controller.isWebRTCOpen ? "WebRTC Direct Channel" : "Handshake Encrypted Link",
                      style: TextStyle(
                        fontSize: 10,
                        color: controller.isWebRTCOpen ? const Color(0xFF00a884) : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Expiration Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF182229),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_bottom, color: Color(0xFFf15c6d), size: 12),
                const SizedBox(width: 4),
                Text(
                  _timeRemainingStr,
                  style: const TextStyle(
                    color: Color(0xFFf15c6d),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            tooltip: "Destroy Conversation",
            onPressed: _destroyRoom,
          ),
        ],
      ),
    );
  }

  Widget _buildKeyMismatchBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF5a1a1a),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "CRITICAL SECURITY WARNING: Pinned identity key mismatch! An eavesdropper may be active on this connection.",
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnverifiedContactBanner(RoomSessionController controller) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF182229),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_open, color: Color(0xFF00a884), size: 16),
                  SizedBox(width: 8),
                  Text(
                    "Handshake Verified. Save peer as Trusted Contact?",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              if (!_showTrustForm)
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 30)),
                  onPressed: () => setState(() => _showTrustForm = true),
                  child: const Text("Save Contact", style: TextStyle(color: Color(0xFF00a884), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
          if (_showTrustForm) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: "Enter contact name (e.g. Alice)",
                        hintStyle: TextStyle(color: Colors.white30, fontSize: 13),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00a884),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    minimumSize: const Size(60, 38),
                  ),
                  onPressed: () => _saveAsTrusted(controller),
                  child: const Text("Trust", style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _showTrustForm = false),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white60, fontSize: 13)),
                )
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSystemBubble(String text) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF182229), // WhatsApp Info bubble
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFffd279), fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildChatBubble(Message msg) {
    final isMe = msg.isMe;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (widget.isEmbedded ? 0.65 : 0.75)),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF005c4b) : const Color(0xFF202c33), // WhatsApp message bubble colors
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 1,
              offset: const Offset(0, 1),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.3),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(
                    color: isMe ? Colors.white54 : Colors.white30,
                    fontSize: 9,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInputFieldBar() {
    return Container(
      color: const Color(0xFF202c33), // WhatsApp Input bar color
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              child: TextField(
                controller: _messageController,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: "Type a message",
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 14.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  filled: true,
                  fillColor: const Color(0xFF2a3942), // WhatsApp input background
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF00a884), // WhatsApp green send button
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 16),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
