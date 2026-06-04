import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/theme_controller.dart';
import '../core/room_session_controller.dart';
import '../models/message.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/identicon.dart';

class ChatScreen extends StatefulWidget {
  final bool isEmbedded;
  const ChatScreen({super.key, this.isEmbedded = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _countdownTimer;
  Timer? _msgExpirationTimer;
  Timer? _pingTimer;
  String _timeRemainingStr = "00:00";
  bool _showTrustForm = false;
  bool _hasPopped = false;
  bool _showWebRTCHUD = false;

  @override
  void initState() {
    super.initState();
    _startTimers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _startTimers() {
    final controller = Provider.of<RoomSessionController>(
      context,
      listen: false,
    );
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
              _timeRemainingStr =
                  "${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
            } else {
              _timeRemainingStr =
                  "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
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

    // 3. Cryptographic ping/pong timer
    _pingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        final ctrl = Provider.of<RoomSessionController>(context, listen: false);
        if (ctrl.activeRoom != null && ctrl.activeRoom!.symmetricKey != null) {
          ctrl.sendPing();
        }
      }
    });
  }

  void _checkMessageExpiration(
    RoomSessionController controller,
    int expirationMinutes,
  ) async {
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
      print(
        "Local message expiration triggered for ${expired.length} messages.",
      );
      setState(() {
        controller.messages.removeWhere(
          (m) => expired.any((e) => e.id == m.id),
        );
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

    final controller = Provider.of<RoomSessionController>(
      context,
      listen: false,
    );
    controller.sendMessage(text);
    _messageController.clear();

    Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
  }

  Future<void> _destroyRoom() async {
    final controller = Provider.of<RoomSessionController>(
      context,
      listen: false,
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Destroy Room?"),
        content: const Text(
          "This will permanently shred and delete all messages from this device and notify the peer. This cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              "Shred & Destroy",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await controller.destroyActiveRoom();
      if (!mounted) return;
      if (!widget.isEmbedded) {
        _hasPopped = true;
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

  Future<void> _showReconnectionSetupDialog(RoomSessionController controller) async {
    final TextEditingController passcodeController = TextEditingController();
    // Auto-generate a random 6-digit passcode
    final randomCode = (100000 + Random().nextInt(900000)).toString();
    passcodeController.text = randomCode;
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Setup Reconnection"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Agree on a passcode with your peer, or copy the auto-generated one below to send it to them. Paste it here on both devices to register.",
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: passcodeController,
                      autofocus: true,
                      maxLength: 16,
                      obscureText: false,
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
                      decoration: const InputDecoration(
                        hintText: "PASSCODE",
                        counterText: "",
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: "Copy passcode",
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: passcodeController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Passcode copied to clipboard.")),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste, size: 20),
                    tooltip: "Paste passcode",
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data != null && data.text != null) {
                        passcodeController.text = data.text!.trim().toUpperCase();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: isLoading
                  ? null
                  : () async {
                      final code = passcodeController.text.trim();
                      if (code.isEmpty || code.length < 4) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Passcode must be at least 4 characters."),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }

                      setDialogState(() {
                        isLoading = true;
                      });

                      final response = await controller.registerReconnection(code);

                      if (mounted) {
                        Navigator.of(context).pop(); // Dismiss dialog
                        if (response['success'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Reconnection passcode submitted! Waiting for peer..."),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Failed: ${response['error']}"),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text("Register", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }


  @override
  void dispose() {
    _countdownTimer?.cancel();
    _msgExpirationTimer?.cancel();
    _pingTimer?.cancel();
    _messageController.dispose();
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget build(BuildContext context) {
    context.watch<ThemeController>();
    final controller = Provider.of<RoomSessionController>(context);
    final room = controller.activeRoom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If room is terminated, pop back to home if not embedded
    if (room == null && controller.status == SessionStatus.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_hasPopped) {
          _hasPopped = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(controller.errorMessage ?? "Room terminated."),
              backgroundColor: AppColors.warning,
            ),
          );
          if (!widget.isEmbedded) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          }
        }
      });
      return _buildEmptyState();
    }

    if (room == null) {
      return _buildEmptyState();
    }

    final String displayName =
        controller.matchedContactName ?? "Peer (${room.id})";

    final chatWidget = Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Header Bar
          _buildHeader(displayName, controller),

          // WebRTC Status HUD
          if (_showWebRTCHUD && room != null) _buildWebRTCHUD(controller),

          // Security Banners
          if (controller.isKeyMismatch) _buildKeyMismatchBanner(),
          if (controller.isPeerVerified &&
              controller.matchedContactName == null)
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
          _buildInputFieldBar(controller),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return chatWidget;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: chatWidget),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_person_outlined,
              size: 64,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              "No active secure room",
              style: TextStyle(
                color: isDark ? Colors.white30 : Colors.black38,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String name, RoomSessionController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white38 : Colors.black45;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.surfaceLight, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (!widget.isEmbedded)
            IconButton(
              icon: Icon(Icons.arrow_back, color: iconColor),
              onPressed: () {
                _hasPopped = true;
                Navigator.of(context).pop();
              },
            ),
          IdenticonWidget(
            publicKeyHex: controller.activeRoom?.peerEd25519PublicKeyHex ?? '',
            size: 40,
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                        fontSize: 15,
                      ),
                    ),
                    if (controller.isPeerVerified) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified,
                        color: AppColors.primary,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showWebRTCHUD = !_showWebRTCHUD;
                    });
                  },
                  child: Row(
                    children: [
                      Icon(
                        controller.isWebRTCOpen
                            ? Icons.shield
                            : Icons.lock_outline,
                        color: controller.isWebRTCOpen
                            ? AppColors.primary
                            : subtextColor,
                        size: 11,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        controller.isWebRTCOpen
                            ? "WebRTC Direct Channel"
                            : "Handshake Encrypted Link",
                        style: TextStyle(
                          fontSize: 10,
                          color: controller.isWebRTCOpen
                              ? AppColors.primary
                              : subtextColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _showWebRTCHUD ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: controller.isWebRTCOpen
                            ? AppColors.primary
                            : subtextColor,
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Expiration Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_bottom,
                  color: Color(0xFFf15c6d),
                  size: 12,
                ),
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
            icon: Icon(Icons.key_outlined, color: iconColor),
            tooltip: "Setup Reconnection",
            onPressed: () => _showReconnectionSetupDialog(controller),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close, color: iconColor),
            tooltip: "Destroy Conversation",
            onPressed: _destroyRoom,
          ),
        ],

      ),
    );
  }

  Widget _buildWebRTCHUD(RoomSessionController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white38 : Colors.black45;
    final rtt = controller.latency;
    
    String latencyStr = "Measuring...";
    Color latencyColor = AppColors.secondary;
    if (rtt != null) {
      latencyStr = "$rtt ms";
      if (rtt < 100) {
        latencyColor = AppColors.success;
      } else if (rtt < 250) {
        latencyColor = AppColors.warning;
      } else {
        latencyColor = AppColors.error;
      }
    }

    final pathStr = controller.isWebRTCOpen
        ? "P2P Direct (WebRTC Data Channel)"
        : "Relayed Link (Signaling Socket Server)";
    final pathColor = controller.isWebRTCOpen ? AppColors.success : AppColors.warning;

    final myX25519 = controller.activeRoom?.myX25519PublicKeyHex ?? "Unknown";
    final peerX25519 = controller.activeRoom?.peerX25519PublicKeyHex ?? "Negotiating...";

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.surfaceLight, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "P2P Connection Telemetry",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showWebRTCHUD = false;
                  });
                },
                child: Icon(Icons.expand_less, size: 18, color: labelColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildHUDItem(
                  "Connection Latency",
                  latencyStr,
                  valueColor: latencyColor,
                ),
              ),
              Expanded(
                child: _buildHUDItem(
                  "Transmission Path",
                  pathStr,
                  valueColor: pathColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildHUDItem(
                  "Local DH Key (X25519)",
                  myX25519.length > 16
                      ? "${myX25519.substring(0, 8)}...${myX25519.substring(myX25519.length - 8)}"
                      : myX25519,
                ),
              ),
              Expanded(
                child: _buildHUDItem(
                  "Peer DH Key (X25519)",
                  peerX25519.length > 16
                      ? "${peerX25519.substring(0, 8)}...${peerX25519.substring(peerX25519.length - 8)}"
                      : peerX25519,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 16, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Encryption Scheme: ChaCha20-Poly1305 (256-bit AEAD)",
                style: TextStyle(fontSize: 10, color: labelColor),
              ),
              Text(
                "Verification Signature: Ed25519",
                style: TextStyle(fontSize: 10, color: labelColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHUDItem(String label, String value, {Color? valueColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor ?? (isDark ? Colors.white70 : Colors.black87),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnverifiedContactBanner(RoomSessionController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bannerBg = isDark ? const Color(0xFF182229) : AppColors.surfaceLight;
    final hintColor = isDark ? Colors.white70 : Colors.black87;

    return Container(
      width: double.infinity,
      color: bannerBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_open, color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    "Handshake Verified. Save peer as Trusted Contact?",
                    style: TextStyle(color: hintColor, fontSize: 12),
                  ),
                ],
              ),
              if (!_showTrustForm)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                  ),
                  onPressed: () => setState(() => _showTrustForm = true),
                  child: Text(
                    "Save Contact",
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          if (_showTrustForm) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: "Enter contact name (e.g. Alice)",
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white30 : Colors.black38,
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    minimumSize: const Size(60, 38),
                  ),
                  onPressed: () => _saveAsTrusted(controller),
                  child: const Text(
                    "Trust",
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _showTrustForm = false),
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSystemBubble(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF182229) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? const Color(0xFFffd279) : const Color(0xFFb47a00),
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(Message msg) {
    final isMe = msg.isMe;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = isMe
        ? AppColors.primary
        : AppColors.surface;

    final textColor = isMe
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    final timeColor = isMe
        ? Colors.white70
        : (isDark ? Colors.white30 : Colors.black38);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              (widget.isEmbedded ? 0.65 : 0.75),
        ),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: textColor,
                fontSize: 14.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(
                    color: timeColor,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputFieldBar(RoomSessionController controller) {
    final room = controller.activeRoom;
    final isConnected = room != null && room.symmetricKey != null;
    final hint = isConnected ? "Type a message" : "Waiting for secure connection...";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final inputColor = isConnected
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? Colors.white30 : Colors.black38);

    final hintTextStyle = TextStyle(
      color: isConnected
          ? (isDark ? Colors.white30 : Colors.black38)
          : (isDark ? Colors.white10 : Colors.black26),
      fontSize: 14.5,
    );

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _messageController,
                maxLines: null,
                enabled: isConnected,
                keyboardType: TextInputType.multiline,
                style: TextStyle(color: inputColor, fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: hintTextStyle,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: isConnected ? (_) => _sendMessage() : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 20,
            backgroundColor: isConnected
                ? AppColors.primary
                : AppColors.surfaceLight,
            child: IconButton(
              icon: Icon(
                Icons.send,
                color: isConnected
                    ? Colors.white
                    : (isDark ? Colors.white30 : Colors.black26),
                size: 16,
              ),
              onPressed: isConnected ? _sendMessage : null,
            ),
          ),
        ],
      ),
    );
  }
}
