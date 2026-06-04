import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemEntity; // Use conditional imports or guard
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../models/trusted_contact.dart';
import 'package:uuid/uuid.dart';


class StorageService {
  static const String _roomsKey = 'encline_recent_rooms';
  static const String _onboardingCompleteKey = 'encline_onboarding_complete';
  static const String _themeModeKey = 'encline_theme_mode';
  static const String _serverUrlKey = 'encline_server_url';
  static const String _contactsKey = 'encline_trusted_contacts';
  static const String _myPrivateKeyKey = 'encline_my_ed25519_private_key';
  static const String _myPublicKeyKey = 'encline_my_ed25519_public_key';
  static const String _deviceIdKey = 'encline_device_id';


  // Helper to get local storage directory
  Future<Directory> get _localDirectory async {
    if (kIsWeb) throw UnsupportedError("File system access not supported on Web");
    return await getApplicationDocumentsDirectory();
  }

  // Get path for a room's messages file
  Future<File> _getMessagesFile(String roomId) async {
    if (kIsWeb) throw UnsupportedError("File system access not supported on Web");
    final dir = await _localDirectory;
    return File('${dir.path}/messages_$roomId.json');
  }

  // 1. SharedPreferences settings

  // Default signaling server URL
  Future<String> getDefaultServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_serverUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      return savedUrl;
    }
    return "https://encline-backend.onrender.com";
  }

  Future<void> setDefaultServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    var sanitizedUrl = url.trim();
    if (sanitizedUrl.isNotEmpty) {
      if (!sanitizedUrl.startsWith('http://') && !sanitizedUrl.startsWith('https://')) {
        sanitizedUrl = 'http://$sanitizedUrl';
      }
    }
    await prefs.setString(_serverUrlKey, sanitizedUrl);
  }

  // Onboarding status
  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  Future<void> setOnboardingComplete(bool complete) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, complete);
  }

  // Theme settings (true for dark, false for light)
  Future<bool> isDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_themeModeKey) ?? true; // Default dark-first
  }

  Future<void> setDarkMode(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeModeKey, dark);
  }

  Future<String?> getMyEd25519PrivateKeyHex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_myPrivateKeyKey);
  }

  Future<String?> getMyEd25519PublicKeyHex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_myPublicKeyKey);
  }

  Future<void> saveMyEd25519Keys(String privateHex, String publicHex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_myPrivateKeyKey, privateHex);
    await prefs.setString(_myPublicKeyKey, publicHex);
  }

  // 1.5 Trusted Contacts Management
  Future<List<TrustedContact>> getTrustedContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_contactsKey) ?? [];
    return list.map((item) => TrustedContact.fromJson(item)).toList();
  }

  Future<void> saveTrustedContact(TrustedContact contact) async {
    final contacts = await getTrustedContacts();
    contacts.removeWhere((c) => c.ed25519PublicKeyHex == contact.ed25519PublicKeyHex);
    contacts.insert(0, contact);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_contactsKey, contacts.map((c) => c.toJson()).toList());
  }

  Future<void> updateContactPasscode(String ed25519PublicKeyHex, String passcode) async {
    final contacts = await getTrustedContacts();
    final index = contacts.indexWhere((c) => c.ed25519PublicKeyHex == ed25519PublicKeyHex);
    if (index != -1) {
      final old = contacts[index];
      contacts[index] = TrustedContact(
        nickname: old.nickname,
        x25519PublicKeyHex: old.x25519PublicKeyHex,
        ed25519PublicKeyHex: old.ed25519PublicKeyHex,
        addedAt: old.addedAt,
        reconnectPasscode: passcode,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_contactsKey, contacts.map((c) => c.toJson()).toList());
    }
  }

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }


  Future<void> removeTrustedContact(String ed25519KeyHex) async {
    final contacts = await getTrustedContacts();
    contacts.removeWhere((c) => c.ed25519PublicKeyHex == ed25519KeyHex);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_contactsKey, contacts.map((c) => c.toJson()).toList());
  }

  // 2. Room management

  // Save or update room in recent list
  Future<void> saveRoom(Room room) async {
    final rooms = await getRecentRooms();
    final index = rooms.indexWhere((r) => r.id == room.id);
    if (index != -1) {
      rooms[index] = room;
    } else {
      rooms.insert(0, room);
    }
    await _saveRoomsList(rooms);
  }

  // Fetch list of recent rooms (filtering out expired ones)
  Future<List<Room>> getRecentRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final roomsJson = prefs.getStringList(_roomsKey) ?? [];
    
    final List<Room> rooms = [];
    final now = DateTime.now();
    bool needsWipe = false;

    for (final jsonStr in roomsJson) {
      try {
        final room = Room.fromJson(jsonStr);
        // If room is not expired, keep it
        if (room.expirationTime.isAfter(now)) {
          rooms.add(room);
        } else {
          // If expired, trigger automatic background destruction of its messages
          needsWipe = true;
          if (kIsWeb) {
            await prefs.remove('messages_${room.id}');
          } else {
            final file = await _getMessagesFile(room.id);
            await _shredFile(file);
          }
        }
      } catch (_) {
        needsWipe = true;
      }
    }

    if (needsWipe) {
      await _saveRoomsList(rooms);
    }

    return rooms;
  }

  Future<void> _saveRoomsList(List<Room> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> roomsJson = rooms.map((r) => r.toJson()).toList();
    await prefs.setStringList(_roomsKey, roomsJson);
  }

  // Remove room from recent list
  Future<void> removeRoomFromRecent(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final roomsJson = prefs.getStringList(_roomsKey) ?? [];
    final List<String> updatedRoomsJson = [];
    for (final jsonStr in roomsJson) {
      try {
        final room = Room.fromJson(jsonStr);
        if (room.id != roomId) {
          updatedRoomsJson.add(jsonStr);
        }
      } catch (_) {}
    }
    await prefs.setStringList(_roomsKey, updatedRoomsJson);
  }

  // 3. Message management

  // Save a new message
  Future<void> saveMessage(Message message) async {
    final messages = await getMessages(message.roomId);
    messages.add(message);
    await _saveMessages(message.roomId, messages);
  }

  // Fetch messages for a room
  Future<List<Message>> getMessages(String roomId) async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = prefs.getString('messages_$roomId') ?? '';
        if (jsonStr.isEmpty) return [];
        final List<dynamic> list = json.decode(jsonStr);
        return list.map((item) => Message.fromMap(item)).toList();
      } catch (_) {
        return [];
      }
    }
    
    try {
      final file = await _getMessagesFile(roomId);
      if (!await file.exists()) {
        return [];
      }
      final jsonStr = await file.readAsString();
      if (jsonStr.isEmpty) return [];
      final List<dynamic> list = json.decode(jsonStr);
      return list.map((item) => Message.fromMap(item)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveMessages(String roomId, List<Message> messages) async {
    final jsonStr = json.encode(messages.map((m) => m.toMap()).toList());
    
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('messages_$roomId', jsonStr);
      return;
    }
    
    final file = await _getMessagesFile(roomId);
    await file.writeAsString(jsonStr, flush: true);
  }

  // 4. Secure Shredding and Wipe Utilities

  // Shreds a file by overwriting its content with zeroes before deleting it
  Future<void> _shredFile(File file) async {
    if (kIsWeb) return;
    if (!await file.exists()) return;
    
    try {
      final length = await file.length();
      if (length > 0) {
        // Create an array of zeroes of the exact file size
        final zeroBytes = Uint8List(length);
        // Overwrite file contents
        await file.writeAsBytes(zeroBytes, flush: true);
      }
      // Delete the file
      await file.delete();
      print("Shredded and deleted file: ${file.path}");
    } catch (e) {
      print("Error shredding file: $e");
      // Fallback: regular delete
      await file.delete();
    }
  }

  // Delete all local data for a specific room (shredding messages and removing recent)
  Future<void> deleteRoomData(String roomId) async {
    // 1. Shred messages file
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('messages_$roomId');
    } else {
      final file = await _getMessagesFile(roomId);
      await _shredFile(file);
    }
    
    // 2. Remove room from recent rooms list directly to avoid recursion
    final prefs = await SharedPreferences.getInstance();
    final roomsJson = prefs.getStringList(_roomsKey) ?? [];
    final List<String> updatedRoomsJson = [];
    for (final jsonStr in roomsJson) {
      try {
        final room = Room.fromJson(jsonStr);
        if (room.id != roomId) {
          updatedRoomsJson.add(jsonStr);
        }
      } catch (_) {}
    }
    await prefs.setStringList(_roomsKey, updatedRoomsJson);
  }

  // Global Wipe: Wipes all application local data (for the Settings screen)
  Future<void> wipeAllData() async {
    // 1. Wipe SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!kIsWeb) {
      // 2. Wipe and shred all messages files in app directory
      final dir = await _localDirectory;
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = await dir.list().toList();
        for (final entity in entities) {
          if (entity is File && entity.path.contains('messages_') && entity.path.endsWith('.json')) {
            await _shredFile(entity);
          }
        }
      }
    }
  }
}
