import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';
import '../core/room_session_controller.dart';
import '../core/storage_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glassmorphic_container.dart';
import 'chat_screen.dart';

class JoinRoomScreen extends StatefulWidget {
  final String? initialInviteLink;
  final bool isEmbedded;
  final VoidCallback? onCancel;

  const JoinRoomScreen({
    Key? key,
    this.initialInviteLink,
    this.isEmbedded = false,
    this.onCancel,
  }) : super(key: key);

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _linkController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  
  bool _isProcessing = false;
  bool _isScanning = kIsWeb; // Default true on Web, false on native until permission granted

  @override
  void initState() {
    super.initState();
    if (widget.initialInviteLink != null) {
      _linkController.text = widget.initialInviteLink!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processInviteLink(widget.initialInviteLink!);
      });
    }
    if (!kIsWeb) {
      _requestCameraPermission();
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      if (mounted) {
        setState(() {
          _isScanning = true;
        });
        _scannerController.start();
      }
    } else {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Camera permission is required to scan QR codes."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // Parse invite links
  Future<void> _processInviteLink(String url) async {
    if (_isProcessing) return;
    
    // Clean URL
    url = url.trim();
    if (url.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final uri = Uri.parse(url);
      
      // Parse parameters from query string
      Map<String, String> params = Map.from(uri.queryParameters);
      
      // Check if hash fragment contains query parameters (typical in Flutter Web)
      if (uri.fragment.isNotEmpty && uri.fragment.contains('?')) {
        final fragParts = uri.fragment.split('?');
        if (fragParts.length > 1) {
          final queryStr = fragParts[1];
          final fragUri = Uri.parse('?$queryStr');
          params.addAll(fragUri.queryParameters);
        }
      }

      final roomId = params['room']?.toUpperCase();
      String? serverUrl = params['server'];
      final x25519Key = params['x25519'];
      final ed25519Key = params['ed25519'];

      if (roomId == null || serverUrl == null || x25519Key == null || ed25519Key == null) {
        throw Exception("Invite link is missing crucial encryption keys or room parameters.");
      }

      // Automatically sanitize localhost/127.0.0.1/10.0.2.2 if remote host context exists
      final serverUri = Uri.tryParse(serverUrl);
      if (serverUri != null) {
        final host = serverUri.host;
        final isLocalhost = host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
        
        if (isLocalhost) {
          if (uri.scheme.startsWith('http')) {
            final inviteHost = uri.host;
            final isInviteLocalhost = inviteHost == 'localhost' || inviteHost == '127.0.0.1' || inviteHost == '10.0.2.2';
            if (!isInviteLocalhost) {
              serverUrl = serverUri.replace(
                host: uri.host,
                port: uri.hasPort ? uri.port : null,
              ).toString();
              print("Join: Rewrote localhost server URL to invite link host -> $serverUrl");
            }
          } else if (kIsWeb) {
            final baseUri = Uri.base;
            if (baseUri.scheme.startsWith('http')) {
              final baseHost = baseUri.host;
              final isBaseLocalhost = baseHost == 'localhost' || baseHost == '127.0.0.1' || baseHost == '10.0.2.2';
              if (!isBaseLocalhost) {
                serverUrl = serverUri.replace(
                  host: baseUri.host,
                  port: baseUri.hasPort ? baseUri.port : null,
                ).toString();
                print("Join: Rewrote localhost server URL to web origin host -> $serverUrl");
              }
            }
          } else {
            // APK Native - replace with saved default server host if it's not localhost itself
            final storage = StorageService();
            final defaultUrl = await storage.getDefaultServerUrl();
            final defaultUri = Uri.tryParse(defaultUrl);
            if (defaultUri != null && defaultUri.scheme.startsWith('http')) {
              final defaultHost = defaultUri.host;
              final isDefaultLocalhost = defaultHost == 'localhost' || defaultHost == '127.0.0.1' || defaultHost == '10.0.2.2';
              if (!isDefaultLocalhost) {
                serverUrl = serverUri.replace(
                  host: defaultUri.host,
                  port: defaultUri.hasPort ? defaultUri.port : null,
                ).toString();
                print("Join: Rewrote localhost server URL to saved default host -> $serverUrl");
              }
            }
          }
        }
      }

      if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
        serverUrl = 'http://$serverUrl';
      }

      // Stop camera scanner first
      await _scannerController.stop();

      final controller = Provider.of<RoomSessionController>(context, listen: false);
      
      // Attempt to join the room
      await controller.joinRoom(
        serverUrl: serverUrl,
        roomId: roomId,
        expectedX25519PublicKeyHex: x25519Key,
        expectedEd25519PublicKeyHex: ed25519Key,
      );

      if (controller.status == SessionStatus.handshakeComplete && controller.activeRoom != null) {
        if (!mounted) return;
        if (widget.isEmbedded) {
          // Embedded parent will switch automatically
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ChatScreen()),
          );
        }
      } else {
        throw Exception(controller.errorMessage ?? "Handshake negotiation failed.");
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error joining room: ${e.toString().replaceAll("Exception: ", "")}"),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );

      // Restart scanner if it was stopped
      if (_isScanning) {
        _scannerController.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isEmbedded ? Colors.transparent : AppColors.background,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text("Join Private Room"),
              actions: [
                IconButton(
                  icon: Icon(
                    _isScanning ? Icons.videocam : Icons.videocam_off,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isScanning = !_isScanning;
                    });
                    if (_isScanning) {
                      _scannerController.start();
                    } else {
                      _scannerController.stop();
                    }
                  },
                )
              ],
            ),
      body: Stack(
        children: [
          // 1. Camera QR Scanner layer
          if (_isScanning && !_isProcessing)
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? rawValue = barcode.rawValue;
                  if (rawValue != null) {
                    print("Barcode detected: $rawValue");
                    _processInviteLink(rawValue);
                    break;
                  }
                }
              },
            ),

          // Custom header for embedded mode
          if (widget.isEmbedded)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white70),
                        onPressed: widget.onCancel,
                      ),
                      const Text(
                        "Join Private Room",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      _isScanning ? Icons.videocam : Icons.videocam_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _isScanning = !_isScanning;
                      });
                      if (_isScanning) {
                        _scannerController.start();
                      } else {
                        _scannerController.stop();
                      }
                    },
                  ),
                ],
              ),
            ),

          // 2. Futuristic scanner HUD Overlay (if scanning)
          if (_isScanning && !_isProcessing)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.secondary, width: 2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    // Corner marks
                    Positioned(
                      top: 10, left: 10,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white, width: 3), left: BorderSide(color: Colors.white, width: 3)))),
                    ),
                    Positioned(
                      top: 10, right: 10,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white, width: 3), right: BorderSide(color: Colors.white, width: 3)))),
                    ),
                    Positioned(
                      bottom: 10, left: 10,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 3), left: BorderSide(color: Colors.white, width: 3)))),
                    ),
                    Positioned(
                      bottom: 10, right: 10,
                      child: Container(width: 20, height: 20, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 3), right: BorderSide(color: Colors.white, width: 3)))),
                    ),
                  ],
                ),
              ),
            ),

          // 3. UI overlays (Controls and fallbacks)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GlassmorphicContainer(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 40),
              borderRadius: 24,
              borderOpacity: 0.1,
              backgroundOpacity: 0.1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Scanner Fallback",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "If the camera cannot scan, paste the invite link below:",
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 16),
                  
                  // Text Input
                  TextField(
                    controller: _linkController,
                    maxLines: 1,
                    enabled: !_isProcessing,
                    decoration: const InputDecoration(
                      hintText: "encline://join?room=...",
                      prefixIcon: Icon(Icons.link, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Join Button
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: "Connect to Room",
                      icon: Icons.login_outlined,
                      isLoading: _isProcessing,
                      onPressed: () => _processInviteLink(_linkController.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      "Connecting and performing X25519 handshake...",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    )
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }
}
