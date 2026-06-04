import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/core/storage_service.dart';
import 'package:frontend/models/room.dart';
import 'package:frontend/models/message.dart';

// Mock PathProvider
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService Tests', () {
    late StorageService storageService;

    setUp(() async {
      // Mock SharedPreferences initial values
      SharedPreferences.setMockInitialValues({});
      
      // Mock PathProvider platform implementation
      PathProviderPlatform.instance = MockPathProviderPlatform();
      
      storageService = StorageService();
    });

    test('Onboarding and Theme Settings Store/Retrieve', () async {
      expect(await storageService.isOnboardingComplete(), isFalse);
      await storageService.setOnboardingComplete(true);
      expect(await storageService.isOnboardingComplete(), isTrue);

      expect(await storageService.isDarkMode(), isTrue); // Default dark
      await storageService.setDarkMode(false);
      expect(await storageService.isDarkMode(), isFalse);
    });

    test('Room Storage Lifecycle', () async {
      final now = DateTime.now();
      final room1 = Room(
        id: 'ROOM11',
        expirationTime: now.add(const Duration(minutes: 5)),
        messageExpirationMinutes: 10,
        isHost: true,
        myX25519PublicKeyHex: 'aabbcc',
        myEd25519PublicKeyHex: 'ddeeff',
      );

      final roomExpired = Room(
        id: 'ROOMEX',
        expirationTime: now.subtract(const Duration(minutes: 5)),
        messageExpirationMinutes: 10,
        isHost: false,
        myX25519PublicKeyHex: '112233',
        myEd25519PublicKeyHex: '445566',
      );

      // Save rooms
      await storageService.saveRoom(room1);
      await storageService.saveRoom(roomExpired);

      // Fetch active rooms (roomExpired should be auto-deleted)
      final recent = await storageService.getRecentRooms();
      
      expect(recent.length, equals(1));
      expect(recent.first.id, equals('ROOM11'));
    });

    test('Message Log and Shredding', () async {
      const roomId = 'TESTSH';
      final msg1 = Message(
        id: 'msg1',
        roomId: roomId,
        senderId: 'me',
        text: 'Hello target message',
        timestamp: DateTime.now(),
      );

      final msg2 = Message(
        id: 'msg2',
        roomId: roomId,
        senderId: 'peer',
        text: 'Reply target message',
        timestamp: DateTime.now(),
        isSystem: false,
      );

      // Save messages
      await storageService.saveMessage(msg1);
      await storageService.saveMessage(msg2);

      // Read messages back
      final list = await storageService.getMessages(roomId);
      expect(list.length, equals(2));
      expect(list[0].text, equals('Hello target message'));
      expect(list[1].text, equals('Reply target message'));

      // Delete room data (which triggers shredding)
      await storageService.deleteRoomData(roomId);

      // Read back, should be empty
      final listAfterShred = await storageService.getMessages(roomId);
      expect(listAfterShred.length, equals(0));
    });
  });
}
