import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  final _x25519 = X25519();
  final _ed25519 = Ed25519();
  final _chaCha20 = Chacha20.poly1305Aead();

  // Helper to convert List<int> to Hex String
  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // Helper to convert Hex String to Uint8List
  static Uint8List hexToBytes(String hex) {
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    final len = hex.length ~/ 2;
    final bytes = Uint8List(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  // 1. Generate Ephemeral X25519 Key Pair
  Future<SimpleKeyPair> generateX25519KeyPair() async {
    return await _x25519.newKeyPair();
  }

  // 2. Generate Ed25519 Signing Key Pair
  Future<SimpleKeyPair> generateEd25519KeyPair() async {
    return await _ed25519.newKeyPair();
  }

  // Extract public key bytes from a KeyPair
  Future<Uint8List> getPublicKeyBytes(SimpleKeyPair keyPair) async {
    final pk = await keyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  // Extract public key as Hex String
  Future<String> getPublicKeyHex(SimpleKeyPair keyPair) async {
    final bytes = await getPublicKeyBytes(keyPair);
    return bytesToHex(bytes);
  }

  // 3. Perform X25519 ECDH Key Agreement to get Shared Secret
  Future<Uint8List> performECDH(SimpleKeyPair myKeyPair, String remoteX25519PublicKeyHex) async {
    final remoteBytes = hexToBytes(remoteX25519PublicKeyHex);
    final remotePublicKey = SimplePublicKey(
      remoteBytes,
      type: KeyPairType.x25519,
    );
    
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: remotePublicKey,
    );
    
    final secretBytes = await sharedSecret.extractBytes();
    return Uint8List.fromList(secretBytes);
  }

  // 4. Derive a Symmetric Key (256-bit) using SHA-256 from the shared secret
  // This serves as our Key Derivation Function (KDF)
  Future<Uint8List> deriveSymmetricKey(Uint8List sharedSecretBytes) async {
    final sha256 = Sha256();
    final hash = await sha256.hash(sharedSecretBytes);
    return Uint8List.fromList(hash.bytes);
  }

  // 5. Encrypt plaintext using ChaCha20-Poly1305
  // Output format: Base64(nonce [12 bytes] + mac [16 bytes] + ciphertext)
  Future<String> encryptChaCha20Poly1305(String plaintext, Uint8List symmetricKey) async {
    final plaintextBytes = utf8.encode(plaintext);
    final secretKey = SecretKey(symmetricKey);
    
    // Generate a random 12-byte nonce (IV)
    final nonce = _chaCha20.newNonce();
    
    final secretBox = await _chaCha20.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    
    // Combine nonce + mac + ciphertext
    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.mac.bytes);
    builder.add(secretBox.cipherText);
    
    return base64.encode(builder.toBytes());
  }

  // 6. Decrypt payload using ChaCha20-Poly1305
  // Input format: Base64(nonce [12 bytes] + mac [16 bytes] + ciphertext)
  Future<String> decryptChaCha20Poly1305(String base64Payload, Uint8List symmetricKey) async {
    try {
      final combinedBytes = base64.decode(base64Payload);
      if (combinedBytes.length < 28) {
        throw Exception("Invalid payload: packet too short");
      }
      
      final nonce = combinedBytes.sublist(0, 12);
      final macBytes = combinedBytes.sublist(12, 28);
      final cipherText = combinedBytes.sublist(28);
      
      final secretKey = SecretKey(symmetricKey);
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );
      
      final decryptedBytes = await _chaCha20.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw Exception("Decryption failed: ${e.toString()}");
    }
  }

  // 7. Sign a message using Ed25519 private key
  Future<String> signMessage(String message, SimpleKeyPair ed25519KeyPair) async {
    final messageBytes = utf8.encode(message);
    final signature = await _ed25519.sign(messageBytes, keyPair: ed25519KeyPair);
    return bytesToHex(signature.bytes);
  }

  // 8. Verify an Ed25519 signature
  Future<bool> verifySignature(String message, String signatureHex, String publicKeyHex) async {
    try {
      final messageBytes = utf8.encode(message);
      final signatureBytes = hexToBytes(signatureHex);
      final publicKeyBytes = hexToBytes(publicKeyHex);
      
      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );
      
      return await _ed25519.verify(messageBytes, signature: signature);
    } catch (e) {
      return false;
    }
  }
}
