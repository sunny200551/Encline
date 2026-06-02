import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/storage_service.dart';
import '../core/theme_controller.dart';
import '../models/trusted_contact.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glassmorphic_container.dart';

class SettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onBack;

  const SettingsScreen({Key? key, this.isEmbedded = false, this.onBack}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  bool _isDark = true;
  late final TextEditingController _serverUrlController;
  bool _isCheckingUpdate = false;
  final String _appVersion = "1.0.1"; // Current local version before update

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final dark = await _storage.isDarkMode();
    final server = await _storage.getDefaultServerUrl();
    setState(() {
      _isDark = dark;
      _serverUrlController.text = server;
    });
  }

  Future<void> _toggleTheme(bool value) async {
    await _storage.setDarkMode(value);
    setState(() {
      _isDark = value;
    });
  }

  Future<void> _saveServerUrl() async {
    var url = _serverUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Server URL cannot be empty."),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    
    await _storage.setDefaultServerUrl(url);
    _serverUrlController.text = url;
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Signaling server URL updated."),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Web app updates are managed via Git/Vercel. Simply reload the browser to apply updates."),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      var serverUrl = _serverUrlController.text.trim();
      if (serverUrl.isEmpty) {
        throw Exception("Server URL is empty. Save a server URL first.");
      }

      if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
        serverUrl = 'http://$serverUrl';
        _serverUrlController.text = serverUrl;
        await _storage.setDefaultServerUrl(serverUrl);
      }

      // Query version from server
      final uri = Uri.parse("$serverUrl/version");
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final serverVersion = data['version'];
        final notes = data['notes'] ?? 'No release notes.';
        final apkUrl = data['apkUrl'];

        if (serverVersion != null && serverVersion != _appVersion) {
          // New version available!
          if (!mounted) return;
          _showUpdateDialog(serverVersion, notes, apkUrl);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("You are on the latest version ($serverVersion)."),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        throw Exception("Server returned status code ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to check for updates: ${e.toString().replaceAll("Exception: ", "")}"),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  void _showUpdateDialog(String version, String notes, String downloadUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Update Available (v$version)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("A new version of ENCLINE is available on the server.", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Release Notes:\n$notes", style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Later"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.of(context).pop();
              
              // If downloadUrl is relative, combine with server URL
              String fullDownloadUrl = downloadUrl;
              if (downloadUrl.startsWith('/')) {
                fullDownloadUrl = "${_serverUrlController.text.trim()}$downloadUrl";
              }

              final uri = Uri.parse(fullDownloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Could not open browser to download: $fullDownloadUrl"),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: const Text("Download Update", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _wipeAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Perform Global Wipe?"),
        content: const Text(
          "This will shred and delete ALL messages, rooms, and settings from this device permanently. Peer devices will not be affected, but they will no longer be able to message this device.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Shred Everything", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.wipeAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All local database records shredded successfully."),
          backgroundColor: AppColors.success,
        ),
      );
      if (widget.isEmbedded) {
        if (widget.onBack != null) widget.onBack!();
      } else {
        Navigator.of(context).pop(); // Back to Home
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final subHintColor = isDark ? Colors.white30 : Colors.black38;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final dividerColor = isDark ? Colors.white10 : Colors.black12;

    return Scaffold(
      backgroundColor: widget.isEmbedded ? Colors.transparent : AppColors.background,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text("Security Settings"),
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isEmbedded) ...[
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: iconColor),
                    onPressed: widget.onBack,
                  ),
                  const Text(
                    "Security Settings",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            // Theme settings Card
            Consumer<ThemeController>(
              builder: (context, themeController, _) {
                return GlassmorphicContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  borderRadius: 16,
                  backgroundOpacity: 0.03,
                  child: SwitchListTile(
                    value: !themeController.isLightTheme,
                    onChanged: (isDarkTheme) {
                      themeController.setTheme(isDarkTheme ? 'techBlue' : 'lightCyber');
                    },
                    title: const Text("Dark Mode"),
                    subtitle: Text("Toggle between premium dark and light theme styles", style: TextStyle(color: hintColor, fontSize: 12)),
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                );
              }
            ),
            const SizedBox(height: 24),

            // Color Palette Selector
            const Text(
              "Theme Accent Color",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassmorphicContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              backgroundOpacity: 0.03,
              child: Consumer<ThemeController>(
                builder: (context, themeController, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Choose a color palette for the interface:",
                        style: TextStyle(fontSize: 12, color: hintColor),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: AppPalettes.all.length,
                          itemBuilder: (context, index) {
                            final palette = AppPalettes.all[index];
                            final isSelected = themeController.currentThemeName == palette.name;
                            return GestureDetector(
                              onTap: () {
                                themeController.setTheme(palette.name);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 16),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? palette.primary : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [palette.primary, palette.secondary],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: palette.primary.withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Active Theme: ${AppPalettes.getByName(themeController.currentThemeName).displayName}",
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Signaling Server Config Section
            const Text(
              "Signaling Server Config",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassmorphicContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              backgroundOpacity: 0.03,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Configure default room and handshake server:",
                    style: TextStyle(fontSize: 12, color: hintColor),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverUrlController,
                    decoration: InputDecoration(
                      hintText: "http://10.0.2.2:3000",
                      prefixIcon: Icon(Icons.dns, color: hintColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: "Save Server Configuration",
                      icon: Icons.save,
                      onPressed: _saveServerUrl,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // App Updates Card
            const Text(
              "App Updates",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassmorphicContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              backgroundOpacity: 0.03,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "App Version",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "v$_appVersion",
                            style: TextStyle(fontSize: 12, color: AppColors.secondary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      _isCheckingUpdate
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                              ),
                              icon: const Icon(Icons.update),
                              label: const Text("Check for Updates"),
                              onPressed: _checkForUpdates,
                            ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Cryptographic Stack card
            const Text(
              "Cryptographic Protocol",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassmorphicContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              backgroundOpacity: 0.05,
              child: Column(
                children: [
                  _CryptoInfoRow(
                    label: "Key Agreement",
                    value: "Diffie-Hellman (X25519)",
                    desc: "Symmetric key negotiated out-of-band.",
                    subTextColor: subTextColor,
                  ),
                  Divider(color: dividerColor),
                  _CryptoInfoRow(
                    label: "Symmetric Encryption",
                    value: "ChaCha20-Poly1305 (AEAD)",
                    desc: "Authentic encryption for all text packages.",
                    subTextColor: subTextColor,
                  ),
                  Divider(color: dividerColor),
                  _CryptoInfoRow(
                    label: "Identity Verification",
                    value: "Ed25519 Signatures",
                    desc: "Ensures peer claims belong to the room.",
                    subTextColor: subTextColor,
                  ),
                  Divider(color: dividerColor),
                  _CryptoInfoRow(
                    label: "Key Derivation (KDF)",
                    value: "SHA-256 Digest",
                    desc: "Symmetric key derived from shared secret.",
                    subTextColor: subTextColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Privacy Guarantee
            const Text(
              "Privacy Guarantees",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassmorphicContainer(
              padding: const EdgeInsets.all(16),
              borderRadius: 16,
              backgroundOpacity: 0.03,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PrivacyPoint(
                    icon: Icons.cloud_off,
                    text: "No messages are ever sent to or stored in a database server.",
                    subTextColor: subTextColor,
                  ),
                  const SizedBox(height: 12),
                  _PrivacyPoint(
                    icon: Icons.location_disabled,
                    text: "Zero telemetry, metrics, analytics, or trackers compiled inside.",
                    subTextColor: subTextColor,
                  ),
                  const SizedBox(height: 12),
                  _PrivacyPoint(
                    icon: Icons.security_update_good,
                    text: "Keys are stored in memory and deleted instantly when rooms close.",
                    subTextColor: subTextColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Trusted Contacts list card
            const Text(
              "Trusted Pinned Contacts",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<TrustedContact>>(
              future: _storage.getTrustedContacts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final contacts = snapshot.data ?? [];
                if (contacts.isEmpty) {
                  return GlassmorphicContainer(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 16,
                    backgroundOpacity: 0.03,
                    child: Center(
                      child: Text(
                        "No trusted contacts pinned yet. Save contact signatures during a chat session.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: hintColor),
                      ),
                    ),
                  );
                }
                return GlassmorphicContainer(
                  padding: const EdgeInsets.all(8),
                  borderRadius: 16,
                  backgroundOpacity: 0.03,
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final c = contacts[index];
                      return ListTile(
                        title: Text(c.nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          "Ed25519 Key: ${c.ed25519PublicKeyHex.substring(0, 8)}...${c.ed25519PublicKeyHex.substring(c.ed25519PublicKeyHex.length - 8)}",
                          style: TextStyle(fontSize: 11, color: hintColor),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () async {
                            await _storage.removeTrustedContact(c.ed25519PublicKeyHex);
                            setState(() {}); // refresh list
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 48),

            // Clear Database button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.error),
                ),
                icon: const Icon(Icons.cleaning_services, color: AppColors.error),
                label: const Text(
                  "Perform Global Shred Wipe",
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                ),
                onPressed: _wipeAllData,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CryptoInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String desc;
  final Color subTextColor;

  const _CryptoInfoRow({
    required this.label,
    required this.value,
    required this.desc,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: subTextColor)),
              Text(value, style: TextStyle(color: AppColors.secondary, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 11, color: subTextColor.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color subTextColor;

  const _PrivacyPoint({required this.icon, required this.text, required this.subTextColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.secondary, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: subTextColor, height: 1.4)),
        ),
      ],
    );
  }
}
