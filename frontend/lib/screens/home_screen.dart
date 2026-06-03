import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/theme_controller.dart';
import '../core/storage_service.dart';
import '../core/room_session_controller.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/identicon.dart';
import '../models/room.dart';
import '../models/trusted_contact.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService();
  List<Room> _recentRooms = [];
  List<TrustedContact> _trustedContacts = [];
  bool _isLoading = true;
  int _currentTab = 0; // 0 for Recent Chats, 1 for Trusted Contacts

  // Desktop viewport active pane: 'welcome', 'create', 'join', 'settings', 'chat'
  String _desktopView = 'welcome';

  @override
  void initState() {
    super.initState();
    _loadRecentRooms();
    _checkForDeepLink();
  }

  void _checkForDeepLink() {
    try {
      final uri = Uri.base;
      String? roomId;

      // Check query parameter
      if (uri.queryParameters.containsKey('room')) {
        roomId = uri.queryParameters['room'];
      }

      // Check hash fragment routing parameters
      if (roomId == null && uri.fragment.isNotEmpty) {
        if (uri.fragment.contains('room=')) {
          final index = uri.fragment.indexOf('?');
          if (index != -1 && index < uri.fragment.length - 1) {
            final queryStr = uri.fragment.substring(index + 1);
            final tempUri = Uri.tryParse('?$queryStr');
            if (tempUri != null && tempUri.queryParameters.containsKey('room')) {
              roomId = tempUri.queryParameters['room'];
            }
          }
        }
      }

      if (roomId != null) {
        print("Home: Deep link detected. Routing automatically to JoinRoomScreen...");
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final double width = MediaQuery.of(context).size.width;
          final bool isDesktop = width >= 720;

          if (isDesktop) {
            setState(() {
              _desktopView = 'join';
            });
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => JoinRoomScreen(initialInviteLink: uri.toString()),
              ),
            ).then((_) => _loadRecentRooms());
          }
        });
      }
    } catch (e) {
      print("Error checking deep link: $e");
    }
  }

  Future<void> _loadRecentRooms() async {
    setState(() => _isLoading = true);
    final rooms = await _storage.getRecentRooms();
    final contacts = await _storage.getTrustedContacts();
    setState(() {
      _recentRooms = rooms;
      _trustedContacts = contacts;
      _isLoading = false;
    });
  }

  Future<void> _deleteRoom(String roomId) async {
    await _storage.deleteRoomData(roomId);
    _loadRecentRooms();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Room data securely shredded."),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _openRecentRoom(Room room) async {
    final controller = Provider.of<RoomSessionController>(context, listen: false);
    await controller.loadRecentRoomMessages(room);

    if (!mounted) return;
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 720;

    if (isDesktop) {
      setState(() {
        _desktopView = 'chat';
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const ChatScreen()),
      ).then((_) => _loadRecentRooms());
    }
  }

  void _reconnectToContact(TrustedContact contact) async {
    final String serverUrl = await _storage.getDefaultServerUrl();
    final TextEditingController idController = TextEditingController();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Secure Reconnect: ${contact.nickname}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Ask ${contact.nickname} for their 6-character Room ID to reconnect. "
              "Your client will cryptographically verify their identity key to prevent MITM.",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              autofocus: true,
              maxLength: 6,
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
              decoration: const InputDecoration(
                hintText: "ROOMID",
                counterText: "",
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () async {
              final roomId = idController.text.trim().toUpperCase();
              if (roomId.length != 6) return;

              Navigator.of(context).pop(); // Dismiss reconnect dialog

              final isDesktop = MediaQuery.of(context).size.width >= 720;
              final controller = Provider.of<RoomSessionController>(context, listen: false);

              // Pin expected Ed25519 key for validation
              controller.expectedEd25519Key = contact.ed25519PublicKeyHex;

              if (isDesktop) {
                setState(() {
                  _desktopView = 'chat';
                });

                try {
                  await controller.joinRoom(
                    serverUrl: serverUrl,
                    roomId: roomId,
                    expectedEd25519PublicKeyHex: contact.ed25519PublicKeyHex,
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                  );
                  setState(() {
                    _desktopView = 'welcome';
                  });
                }
              } else {
                // Show loading spinner
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  await controller.joinRoom(
                    serverUrl: serverUrl,
                    roomId: roomId,
                    expectedEd25519PublicKeyHex: contact.ed25519PublicKeyHex,
                  );
                  if (mounted) {
                    Navigator.of(context).pop(); // Dismiss spinner
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const ChatScreen()),
                    ).then((_) => _loadRecentRooms());
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop(); // Dismiss spinner
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                    );
                  }
                }
              }
            },
            child: const Text("Connect & Verify", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeController>();
    final double width = MediaQuery.of(context).size.width;
    final bool isDesktop = width >= 720;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final controller = context.watch<RoomSessionController>();

    // Dynamic split screen router
    if (isDesktop &&
        controller.activeRoom != null &&
        controller.status != SessionStatus.disconnected &&
        controller.status != SessionStatus.waitingForPeer &&
        controller.status != SessionStatus.creatingRoom &&
        controller.status != SessionStatus.connectingSignaling) {
      if (_desktopView != 'chat') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _desktopView = 'chat';
          });
        });
      }
    } else if (isDesktop && controller.activeRoom == null && _desktopView == 'chat') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _desktopView = 'welcome';
        });
      });
    }

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            // Left Sidebar Pane
            Container(
              width: width * 0.35 > 320 ? (width * 0.35 < 400 ? width * 0.35 : 400) : 320,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.surfaceLight, width: 0.5)),
                color: isDark ? AppColors.surface : AppColors.background,
              ),
              child: _buildSidebar(true, controller),
            ),
            
            // Right Content Area
            Expanded(
              child: _buildRightPane(controller),
            ),
          ],
        ),
      );
    }

    // Mobile Viewport
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -150,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.06),
                    blurRadius: 100,
                  )
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _buildSidebar(false, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isDesktop, RoomSessionController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final subHintColor = isDark ? Colors.white30 : Colors.black38;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar Header
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 16 : 4,
            vertical: isDesktop ? 14 : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "ENCLINE",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    "Secure Ephemeral Rooms",
                    style: TextStyle(
                      fontSize: 11,
                      color: hintColor,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: iconColor),
                    onPressed: () {
                      if (isDesktop) {
                        setState(() {
                          _desktopView = 'settings';
                        });
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        ).then((_) => _loadRecentRooms());
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Encryption Engine Status Badge
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 4),
          child: GlassmorphicContainer(
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            backgroundOpacity: 0.03,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success.withValues(alpha: 0.15),
                  ),
                  child: const Icon(Icons.verified_user, color: AppColors.success, size: 16),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "E2EE Shield Active",
                      style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13),
                    ),
                    Text(
                      "X25519 & ChaCha20-Poly1305",
                      style: TextStyle(fontSize: 10, color: hintColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Core Actions
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 4),
          child: Row(
            children: [
              Expanded(
                child: GradientButton(
                  text: "Create",
                  icon: Icons.add,
                  glow: AppGlow.primaryGlow,
                  onPressed: () {
                    if (isDesktop) {
                      setState(() {
                        _desktopView = 'create';
                      });
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const CreateRoomScreen()),
                      ).then((_) => _loadRecentRooms());
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  text: "Join",
                  icon: Icons.qr_code_scanner,
                  gradient: AppColors.accentGradient,
                  glow: AppGlow.accentGlow,
                  onPressed: () {
                    if (isDesktop) {
                      setState(() {
                        _desktopView = 'join';
                      });
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const JoinRoomScreen()),
                      ).then((_) => _loadRecentRooms());
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tabs: Recent Rooms vs Contacts
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 4),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentTab = 0),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: _currentTab == 0 ? AppColors.surfaceLight : Colors.transparent,
                      ),
                      child: Text(
                        "Recent Chats",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _currentTab == 0 ? FontWeight.bold : FontWeight.normal,
                          color: _currentTab == 0 ? textColor : hintColor,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currentTab = 1),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: _currentTab == 1 ? AppColors.surfaceLight : Colors.transparent,
                      ),
                      child: Text(
                        "Trusted Keys",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _currentTab == 1 ? FontWeight.bold : FontWeight.normal,
                          color: _currentTab == 1 ? textColor : hintColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // List Area
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 0),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _currentTab == 0
                    ? _buildRoomsList(isDesktop, controller)
                    : _buildContactsList(isDesktop),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomsList(bool isDesktop, RoomSessionController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final subHintColor = isDark ? Colors.white30 : Colors.black38;

    if (_recentRooms.isEmpty) {
      return Center(
        child: Text(
          "No recent sessions.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: hintColor,
            fontSize: 13,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _recentRooms.length,
      itemBuilder: (context, index) {
        final room = _recentRooms[index];
        final remaining = room.remainingSeconds;
        final minutes = remaining ~/ 60;
        final seconds = remaining % 60;
        final isActive = controller.activeRoom?.id == room.id;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isActive ? AppColors.surfaceLight : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isActive 
                  ? AppColors.primary.withValues(alpha: 0.5) 
                  : (isDark ? AppColors.surfaceLight.withValues(alpha: 0.2) : AppColors.surfaceLight),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: CircleAvatar(
              backgroundColor: (room.isHost ? AppColors.primary : AppColors.accent).withValues(alpha: 0.15),
              radius: 18,
              child: Icon(
                room.isHost ? Icons.dns_outlined : Icons.supervised_user_circle_outlined,
                color: room.isHost ? AppColors.primary : AppColors.accent,
                size: 18,
              ),
            ),
            title: Text(
              "Room: ${room.id}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            subtitle: Text(
              "Expires: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}",
              style: TextStyle(color: hintColor, fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                  onPressed: () => _deleteRoom(room.id),
                ),
                Icon(Icons.chevron_right, color: subHintColor, size: 16),
              ],
            ),
            onTap: () => _openRecentRoom(room),
          ),
        );
      },
    );
  }

  Widget _buildContactsList(bool isDesktop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final subHintColor = isDark ? Colors.white30 : Colors.black38;

    if (_trustedContacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "No trusted keys pinned.\nSave peers during active sessions.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: hintColor,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _trustedContacts.length,
      itemBuilder: (context, index) {
        final contact = _trustedContacts[index];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? AppColors.surfaceLight.withValues(alpha: 0.2) : AppColors.surfaceLight,
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: IdenticonWidget(
              publicKeyHex: contact.ed25519PublicKeyHex,
              size: 36,
            ),
            title: Text(
              contact.nickname,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            subtitle: Text(
              "Key: ${contact.ed25519PublicKeyHex.substring(0, 6)}...${contact.ed25519PublicKeyHex.substring(contact.ed25519PublicKeyHex.length - 6)}",
              style: TextStyle(color: subHintColor, fontSize: 10),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Reconnect",
                style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            onTap: () => _reconnectToContact(contact),
          ),
        );
      },
    );
  }

  Widget _buildRightPane(RoomSessionController controller) {
    switch (_desktopView) {
      case 'create':
        return CreateRoomScreen(
          isEmbedded: true,
          onEnterChat: () {
            setState(() {
              _desktopView = 'chat';
            });
          },
          onCancel: () {
            setState(() {
              _desktopView = 'welcome';
            });
            _loadRecentRooms();
          },
        );
      case 'join':
        return JoinRoomScreen(
          isEmbedded: true,
          onCancel: () {
            setState(() {
              _desktopView = 'welcome';
            });
            _loadRecentRooms();
          },
        );
      case 'settings':
        return SettingsScreen(
          isEmbedded: true,
          onBack: () {
            setState(() {
              _desktopView = 'welcome';
            });
            _loadRecentRooms();
          },
        );
      case 'chat':
        if (controller.activeRoom == null) {
          return _buildWelcomeState();
        }
        return const ChatScreen(isEmbedded: true);
      case 'welcome':
      default:
        return _buildWelcomeState();
    }
  }

  Widget _buildWelcomeState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final subHintColor = isDark ? Colors.white30 : Colors.black38;

    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
              child: Icon(
                Icons.vpn_lock_outlined,
                size: 80,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "ENCLINE Secure Messaging",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              "Temporary E2EE Rooms. Absolutely Zero Server Logging.\nCreate or Join a room from the sidebar to establish a secure link.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: hintColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 14, color: subHintColor),
                const SizedBox(width: 6),
                Text(
                  "ChaCha20-Poly1305 & X25519 ECDH Protected",
                  style: TextStyle(fontSize: 11, color: subHintColor),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
