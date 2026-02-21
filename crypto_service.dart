// lib/services/crypto_service.dart
//
// ECDH P-256 key exchange + AES-256-GCM encryption
// Uses pointycastle (pure Dart, no native deps)

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class CryptoService {
  // Our ephemeral key pair
  AsymmetricKeyPair<PublicKey, PrivateKey>? _keyPair;

  // Derived shared AES key bytes
  Uint8List? _sharedKeyBytes;

  bool get hasSharedKey => _sharedKeyBytes != null;

  // ── Key Generation ─────────────────────────────────────────────────

  Future<void> init() async {
    _keyPair = _generateKeyPair();
  }

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateKeyPair() {
    final keyParams = ECKeyGeneratorParameters(ECCurve_prime256v1());
    final secureRandom = FortunaRandom();
    final seed = Uint8List(32);
    final rng = Random.secure();
    for (int i = 0; i < 32; i++) seed[i] = rng.nextInt(256);
    secureRandom.seed(KeyParameter(seed));

    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(keyParams, secureRandom));
    return generator.generateKeyPair();
  }

  // ── Key Export/Import ──────────────────────────────────────────────

  /// Export our public key as base64 (uncompressed point)
  String exportPublicKey() {
    final pub = _keyPair!.publicKey as ECPublicKey;
    final q = pub.Q!;
    final x = _bigIntToBytes(q.x!.toBigInteger()!, 32);
    final y = _bigIntToBytes(q.y!.toBigInteger()!, 32);
    final uncompressed = Uint8List(65);
    uncompressed[0] = 0x04;
    uncompressed.setRange(1, 33, x);
    uncompressed.setRange(33, 65, y);
    return base64Encode(uncompressed);
  }

  /// Import peer public key and derive shared AES-256 key via ECDH
  void deriveSharedKey(String peerPubKeyB64) {
    final peerBytes = base64Decode(peerPubKeyB64);

    final curve = ECCurve_prime256v1();
    final domainParams = ECDomainParametersImpl('prime256v1', curve);

    // Decode uncompressed point
    final x = _bytesToBigInt(peerBytes.sublist(1, 33));
    final y = _bytesToBigInt(peerBytes.sublist(33, 65));
    final point = curve.curve.createPoint(x, y);
    final peerPublicKey = ECPublicKey(point, domainParams);

    // ECDH: shared_secret = private_key * peer_public_key
    final priv = _keyPair!.privateKey as ECPrivateKey;
    final agreement = ECDHBasicAgreement()..init(priv);
    final sharedSecret = agreement.calculateAgreement(peerPublicKey);

    // KDF: SHA-256(shared_secret)  → 32-byte AES key
    final secretBytes = _bigIntToBytes(sharedSecret, 32);
    final digest = SHA256Digest();
    _sharedKeyBytes = Uint8List(32);
    digest.update(secretBytes, 0, secretBytes.length);
    digest.doFinal(_sharedKeyBytes!, 0);
  }

  // ── Encrypt / Decrypt (AES-256-GCM) ───────────────────────────────

  /// Returns JSON string: { "iv": "...", "ct": "..." }
  String encrypt(String plaintext) {
    if (_sharedKeyBytes == null) throw StateError('No shared key');

    final iv = _randomBytes(12);
    final key = KeyParameter(_sharedKeyBytes!);
    final params = AEADParameters(key, 128, iv, Uint8List(0));

    final cipher = GCMBlockCipher(AESEngine())..init(true, params);
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = Uint8List(cipher.getOutputSize(input.length));
    int offset = cipher.processBytes(input, 0, input.length, output, 0);
    cipher.doFinal(output, offset);

    return jsonEncode({
      'iv': base64Encode(iv),
      'ct': base64Encode(output),
    });
  }

  /// Decrypts a JSON string produced by encrypt()
  String decrypt(String encJson) {
    if (_sharedKeyBytes == null) throw StateError('No shared key');

    final map = jsonDecode(encJson) as Map<String, dynamic>;
    final iv = base64Decode(map['iv'] as String);
    final ct = base64Decode(map['ct'] as String);

    final key = KeyParameter(_sharedKeyBytes!);
    final params = AEADParameters(key, 128, iv, Uint8List(0));

    final cipher = GCMBlockCipher(AESEngine())..init(false, params);
    final output = Uint8List(cipher.getOutputSize(ct.length));
    int offset = cipher.processBytes(ct, 0, ct.length, output, 0);
    cipher.doFinal(output, offset);

    return utf8.decode(output);
  }

  // ── Fingerprint ────────────────────────────────────────────────────

  String fingerprint() {
    final pub = exportPublicKey();
    final bytes = base64Decode(pub);
    final digest = SHA256Digest();
    final hash = Uint8List(32);
    digest.update(bytes, 0, bytes.length);
    digest.doFinal(hash, 0);
    final hex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    // Format as: XXXX XXXX XXXX XXXX
    return hex.substring(0, 32).replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim();
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  Uint8List _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList(
      List.generate(length, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
    );
  }

  BigInt _bytesToBigInt(List<int> bytes) {
    return bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));
  }
}
