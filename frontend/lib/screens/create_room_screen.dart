import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/constants.dart';
import '../core/theme_controller.dart';
import '../core/room_session_controller.dart';
import '../core/storage_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glassmorphic_container.dart';
import 'chat_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onEnterChat;
  final VoidCallback? onCancel;

  const CreateRoomScreen({
    Key? key,
    this.isEmbedded = false,
    this.onEnterChat,
    this.onCancel,
  }) : super(key: key);

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final StorageService _storage = StorageService();
  late final TextEditingController _serverController;
  late final TextEditingController _customCodeController;
  
  // Configurations
  int _roomExpirationIndex = 0;
  final List<int> _roomExpirationOptions = [5, 15, 30, 60, 1440]; // in minutes
  final List<String> _roomExpirationLabels = ["5 Mins", "15 Mins", "30 Mins", "1 Hour", "24 Hours"];

  int _messageExpirationIndex = 1;
  final List<int> _messageExpirationOptions = [1, 5, 10, 30, 0]; // in minutes, 0 = off
  final List<String> _messageExpirationLabels = ["1 Min", "5 Mins", "10 Mins", "30 Mins", "Never"];

  String _inviteLink = "";
  bool _useCustomCode = false;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController();
    _customCodeController = TextEditingController();
    _loadDefaultServer();
  }

  Future<void> _loadDefaultServer() async {
    final url = await _storage.getDefaultServerUrl();
    setState(() {
      _serverController.text = url;
    });
  }

  Future<void> _generateRoom() async {
    var serverUrl = _serverController.text.trim();
    if (serverUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a signaling server URL")),
      );
      return;
    }

    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'http://$serverUrl';
    }

    final controller = Provider.of<RoomSessionController>(context, listen: false);
    
    String? customId;
    if (_useCustomCode) {
      customId = _customCodeController.text.trim().toUpperCase();
      if (customId.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Custom code must be exactly 10 characters")),
        );
        return;
      }
      final codeRegex = RegExp(r'^[A-Z0-9]{10}$');
      if (!codeRegex.hasMatch(customId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Custom code must contain only alphanumeric characters")),
        );
        return;
      }
    }

    // Call controller to create room
    await controller.createRoom(
      serverUrl: serverUrl,
      roomExpirationMinutes: _roomExpirationOptions[_roomExpirationIndex],
      messageExpirationMinutes: _messageExpirationOptions[_messageExpirationIndex],
      customRoomId: customId,
    );

    if (controller.status == SessionStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? "Failed to create room"),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _copyInviteLink() {
    Clipboard.setData(ClipboardData(text: _inviteLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Invite link copied to clipboard!"),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _customCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeController>();
    final controller = Provider.of<RoomSessionController>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final subHintColor = isDark ? Colors.white30 : Colors.black38;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    final isRoomCreated = controller.activeRoom != null &&
        (controller.status == SessionStatus.waitingForPeer ||
            controller.status == SessionStatus.negotiatingEncryption ||
            controller.status == SessionStatus.handshakeComplete);

    if (isRoomCreated && _inviteLink.isEmpty) {
      final room = controller.activeRoom!;
      final serverUrl = controller.connectedServerUrl ?? _serverController.text.trim();
      final encodedServer = Uri.encodeComponent(serverUrl);
      
      if (kIsWeb) {
        final origin = Uri.base.origin;
        _inviteLink = "$origin/#/join?room=${room.id}&server=$encodedServer&x25519=${room.myX25519PublicKeyHex}&ed25519=${room.myEd25519PublicKeyHex}";
      } else {
        final serverUri = Uri.tryParse(serverUrl);
        if (serverUri != null && serverUri.scheme.startsWith('http')) {
          final portStr = serverUri.hasPort ? ":${serverUri.port}" : "";
          _inviteLink = "${serverUri.scheme}://${serverUri.host}$portStr/#/join?room=${room.id}&server=$encodedServer&x25519=${room.myX25519PublicKeyHex}&ed25519=${room.myEd25519PublicKeyHex}";
        } else {
          _inviteLink = "encline://join?room=${room.id}&server=$encodedServer&x25519=${room.myX25519PublicKeyHex}&ed25519=${room.myEd25519PublicKeyHex}";
        }
      }
    }

    return Scaffold(
      backgroundColor: widget.isEmbedded ? Colors.transparent : AppColors.background,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text("Create Privacy Room"),
            ),
      body: Stack(
        children: [
          // Background subtle cyber glow
          Positioned(
            top: 200,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.04),
                    blurRadius: 100,
                  )
                ],
              ),
            ),
          ),
          
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isEmbedded) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: iconColor),
                        onPressed: widget.onCancel,
                      ),
                      const Text(
                        "Create Privacy Room",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (!isRoomCreated) ...[
                  // 1. Server Configuration
                  const Text("Signaling Server", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _serverController,
                    decoration: InputDecoration(
                      hintText: "http://10.0.2.2:3000",
                      prefixIcon: Icon(Icons.dns, color: hintColor),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. Room Expiration
                  const Text("Room Lifespan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("The room will self-destruct after this duration.", style: TextStyle(fontSize: 12, color: hintColor)),
                  const SizedBox(height: 12),
                  _buildSegmentedControl(
                    options: _roomExpirationLabels,
                    currentIndex: _roomExpirationIndex,
                    onSelected: (idx) => setState(() => _roomExpirationIndex = idx),
                    selectedColor: AppColors.primary,
                  ),
                  const SizedBox(height: 24),

                  // 3. Message auto-shred expiration
                  const Text("Message Expiration (Local)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("Messages will delete from local storage after this duration.", style: TextStyle(fontSize: 12, color: hintColor)),
                  const SizedBox(height: 12),
                  _buildSegmentedControl(
                    options: _messageExpirationLabels,
                    currentIndex: _messageExpirationIndex,
                    onSelected: (idx) => setState(() => _messageExpirationIndex = idx),
                    selectedColor: AppColors.accent,
                  ),
                  const SizedBox(height: 24),

                  // 4. Custom Room ID Toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Personal Connect Code", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("Connect distance users without QR/Link sharing", style: TextStyle(fontSize: 12, color: hintColor)),
                        ],
                      ),
                      Switch(
                        value: _useCustomCode,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() {
                            _useCustomCode = val;
                          });
                        },
                      ),
                    ],
                  ),
                  if (_useCustomCode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customCodeController,
                      maxLength: 10,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                      ],
                      decoration: InputDecoration(
                        hintText: "ENTER10CHR",
                        counterText: "",
                        prefixIcon: Icon(Icons.vpn_key, color: hintColor),
                        helperText: "Exactly 10 letters or numbers.",
                        helperStyle: TextStyle(color: subHintColor, fontSize: 11),
                      ),
                    ),
                  ],
                  const SizedBox(height: 48),

                  // Action Trigger
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: "Generate Secure Room",
                      icon: Icons.vpn_lock,
                      isLoading: controller.status == SessionStatus.connectingSignaling ||
                          controller.status == SessionStatus.creatingRoom,
                      onPressed: _generateRoom,
                    ),
                  ),
                  if (controller.status == SessionStatus.connectingSignaling ||
                      controller.status == SessionStatus.creatingRoom) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        controller.status == SessionStatus.connectingSignaling
                            ? "Connecting to secure server...\n(Free Render servers take up to 60s to wake up if asleep)"
                            : "Setting up your private room...",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: hintColor, height: 1.4),
                      ),
                    ),
                  ],
                ] else ...[
                  // Room is created, display QR code and Invite info
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const Icon(Icons.task_alt, color: AppColors.success, size: 54),
                        const SizedBox(height: 8),
                        const Text(
                          "Room Secured",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Room ID: ${controller.activeRoom!.id}",
                          style: TextStyle(fontSize: 16, color: AppColors.secondary, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                        const SizedBox(height: 32),

                        // QR Code container
                        GlassmorphicContainer(
                          padding: const EdgeInsets.all(24),
                          borderRadius: 24,
                          backgroundOpacity: 0.08,
                          child: QrImageView(
                            data: _inviteLink,
                            version: QrVersions.auto,
                            size: 200.0,
                            gapless: false,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        
                        Text(
                          "Share the QR code or link with a peer.\nConnection is secured with X25519 key exchange.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: hintColor),
                        ),
                        const SizedBox(height: 32),

                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: AppColors.primary),
                                ),
                                icon: Icon(Icons.copy, color: AppColors.primary),
                                label: Text("Copy Link", style: TextStyle(color: AppColors.primary)),
                                onPressed: _copyInviteLink,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: GradientButton(
                                text: "Enter Chat",
                                icon: Icons.chat_bubble_outline,
                                glow: AppGlow.primaryGlow,
                                onPressed: () {
                                  if (widget.isEmbedded) {
                                    if (widget.onEnterChat != null) {
                                      widget.onEnterChat!();
                                    }
                                  } else {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(builder: (context) => const ChatScreen()),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl({
    required List<String> options,
    required int currentIndex,
    required ValueChanged<int> onSelected,
    required Color selectedColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: List.generate(options.length, (idx) {
          final isSelected = currentIndex == idx;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isSelected ? selectedColor : Colors.transparent,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: selectedColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: -1,
                          )
                        ]
                      : null,
                ),
                child: Text(
                  options[idx],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
