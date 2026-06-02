import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/encryption_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EncryptionService Tests', () {
    late EncryptionService encryptionService;

    setUp(() {
      encryptionService = EncryptionService();
    });

    test('X25519 Key Generation and ECDH Agreement', () async {
      // 1. Generate keypairs for Alice and Bob
      final aliceXPair = await encryptionService.generateX25519KeyPair();
      final bobXPair = await encryptionService.generateX25519KeyPair();

      final alicePublicKeyHex = await encryptionService.getPublicKeyHex(aliceXPair);
      final bobPublicKeyHex = await encryptionService.getPublicKeyHex(bobXPair);

      expect(alicePublicKeyHex, isNotEmpty);
      expect(bobPublicKeyHex, isNotEmpty);
      expect(alicePublicKeyHex, isNot(equals(bobPublicKeyHex)));

      // 2. Perform ECDH key exchange
      final aliceSharedSecret = await encryptionService.performECDH(aliceXPair, bobPublicKeyHex);
      final bobSharedSecret = await encryptionService.performECDH(bobXPair, alicePublicKeyHex);

      // Verify shared secrets match
      expect(aliceSharedSecret, equals(bobSharedSecret));

      // 3. Derive symmetric key
      final aliceSymmetricKey = await encryptionService.deriveSymmetricKey(aliceSharedSecret);
      final bobSymmetricKey = await encryptionService.deriveSymmetricKey(bobSharedSecret);

      expect(aliceSymmetricKey, equals(bobSymmetricKey));
      expect(aliceSymmetricKey.length, equals(32)); // 256-bit key
    });

    test('ChaCha20-Poly1305 Encryption and Decryption', () async {
      final aliceXPair = await encryptionService.generateX25519KeyPair();
      final bobXPair = await encryptionService.generateX25519KeyPair();

      final alicePublicKeyHex = await encryptionService.getPublicKeyHex(aliceXPair);
      final bobSharedSecret = await encryptionService.performECDH(bobXPair, alicePublicKeyHex);
      final symmetricKey = await encryptionService.deriveSymmetricKey(bobSharedSecret);

      const plaintext = "Hello Encline, this is a secure end-to-end encrypted message!";

      // Encrypt
      final encryptedPayload = await encryptionService.encryptChaCha20Poly1305(plaintext, symmetricKey);
      expect(encryptedPayload, isNotEmpty);
      expect(encryptedPayload, isNot(equals(plaintext)));

      // Decrypt
      final decryptedtext = await encryptionService.decryptChaCha20Poly1305(encryptedPayload, symmetricKey);
      expect(decryptedtext, equals(plaintext));
    });

    test('Ed25519 Signature and Verification', () async {
      final keyPair = await encryptionService.generateEd25519KeyPair();
      final publicKeyHex = await encryptionService.getPublicKeyHex(keyPair);

      const message = "Validate this message integrity.";

      // Sign
      final signatureHex = await encryptionService.signMessage(message, keyPair);
      expect(signatureHex, isNotEmpty);

      // Verify
      final isValid = await encryptionService.verifySignature(message, signatureHex, publicKeyHex);
      expect(isValid, isTrue);

      // Verify fake signature fails
      final isFakeValid = await encryptionService.verifySignature("Altered message", signatureHex, publicKeyHex);
      expect(isFakeValid, isFalse);
    });
  });
}
