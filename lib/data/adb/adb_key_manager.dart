import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/adb_crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:crypto/crypto.dart';

import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:firestick_adb_remote/data/adb/constants.dart';

class AdbKeyManager {
  final FlutterSecureStorage _storage;

  pc.AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _keyPair;
  AdbCrypto? _crypto;
  bool _cryptoReady = false;
  bool _keysAuthorized = false;
  String? _keyFingerprint;
  String? _publicKeyPem;

  AdbKeyManager(this._storage);

  // Getters
  AdbCrypto? get crypto => _crypto;
  bool get cryptoReady => _cryptoReady;
  bool get keysAuthorized => _keysAuthorized;
  String? get keyFingerprint => _keyFingerprint;
  String? getPublicKeyPem() => _publicKeyPem;

  Future<String?> getPublicKeyPemAsync() async {
    return await _storage.read(key: publicKeyKey);
  }

  RSAPublicKey? getPublicKey() {
    return _keyPair?.publicKey;
  }

  Future<void> initialize() async {
    debugPrint("🔑 Initializing AdbKeyManager");
    await LogService.instance.log("🔑 Initializing AdbKeyManager");

    await _restoreCrypto();

    final authStatus = await _storage.read(key: keysAuthorizedKey);
    _keysAuthorized = authStatus == 'true';

    debugPrint(
      "✅ KeyManager init: KeysAuth=$_keysAuthorized, Fingerprint=$_keyFingerprint",
    );
  }

  Future<void> _restoreCrypto() async {
    debugPrint("🔑 Restoring crypto keys from secure storage");
    await LogService.instance.log("🔑 Restoring crypto keys from secure storage");

    final pubPem = await _storage.read(key: publicKeyKey);
    final privPem = await _storage.read(key: privateKeyKey);

    // If both PEMs exist -> attempt to initialize keypair from them
    if (pubPem != null && privPem != null && pubPem.isNotEmpty && privPem.isNotEmpty) {
      debugPrint("Stored key lengths: pub=${pubPem.length}, priv=${privPem.length}");

      try {
        // 1) Try parsing public key (usually works)
        RSAPublicKey publicKey;
        try {
          publicKey = CryptoUtils.rsaPublicKeyFromPem(pubPem) as RSAPublicKey;
        } catch (e) {
          debugPrint("Could not parse stored public key PEM: $e");
          throw Exception("Public key parse failed");
        }

        // // 2) Try parsing private key directly (works when basic_utils can handle the PEM)
        RSAPrivateKey? privateKey;
        // var privateParsed = false;
        // debugPrint("Private: $privPem");
        // try {
        //   privateKey = CryptoUtils.rsaPrivateKeyFromPem(privPem) as RSAPrivateKey;
        //   privateParsed = true;
        //   debugPrint("Parsed private key directly using basic_utils");
        // } catch (e) {
        //   debugPrint("Direct private key parse failed: $e");
        // }

        // 3) If direct parse failed, attempt PKCS#1 -> PKCS#8 wrapping (manual DER assembly)
        // if (!privateParsed) {
          debugPrint("Attempting PKCS#1 -> PKCS#8 conversion for private key...");
          try {
            final pkcs8Pem = _convertPkcs1PemToPkcs8Pem(privPem);
            privateKey = CryptoUtils.rsaPrivateKeyFromPem(pkcs8Pem) as RSAPrivateKey;
            // privateParsed = true;
            debugPrint("Parsed private key after PKCS#8 conversion");
            // Replace privPem variable with pkcs8Pem so file write/verify uses stable format if desired.
          } catch (e) {
            debugPrint("PKCS#1 -> PKCS#8 conversion failed: $e");
          }
        // }

        // if (!privateParsed || privateKey == null) {
        //   throw Exception("Private key parsing failed after all attempts");
        // }

        // 4) Build keypair and initialize AdbCrypto
        _keyPair = pc.AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(publicKey, privateKey!);
        _crypto = AdbCrypto(keyPair: _keyPair!);

        _verifyPublicKeyFormat();

        await _testSignature();
        // After parsing public and private keys successfully
        // Test that AdbCrypto can actually use this keypair
        try {
          final testCrypto = AdbCrypto(keyPair: _keyPair!);
          final testToken = Uint8List.fromList([1, 2, 3, 4]);
          final testSig = testCrypto.signAdbTokenPayload(testToken);
          
          if (testSig.isEmpty) {
            debugPrint("❌ Signing test failed - regenerating keys");
            throw Exception("Keypair signing failed");
          }
          
          _crypto = testCrypto;
          debugPrint("✅ Keypair signing test passed");
        } catch (e) {
          debugPrint("❌ Crypto initialization failed: $e");
          throw e;
        }

        _publicKeyPem = _normalizePemNewlines(pubPem);
        // compute fingerprint from the public key's ssh-rsa blob (consistent)
        _keyFingerprint = computeAndroidAdbFingerprint(_publicKeyPem!);

        debugPrint("✅ RESTORED fingerprint: $_keyFingerprint");
        _cryptoReady = true;
        return;
      } catch (e, st) {
        debugPrint("ℹ️ Failed to load stored PEMs: $e\n$st — regenerating keys");
        // Fallthrough to generate new keys below
      }
    } else {
      debugPrint("No stored keypair found in secure storage");
    }

    // No valid stored keys => generate & persist
    await _generateNewKeypair();
    _cryptoReady = _crypto != null;
  }
// In AdbKeyManager after crypto is initialized
Future<void> _verifyPublicKeyFormat() async {
  if (_crypto == null || _keyPair == null) return;
  
  final publicKeyBytes = _crypto!.getAdbPublicKeyPayload();
  
  // Use flutter_adb's conversion (should be identical to what's sent)
  final androidKeyBytes = AdbCrypto.convertRsaPublicKeyToAdbFormat(_keyPair!.publicKey);
  final base64Key = base64.encode(androidKeyBytes);
  final expectedPayload = utf8.encode('$base64Key unknown@unknown\x00');
  
  debugPrint("Public key bytes length: ${publicKeyBytes.length}");
  debugPrint("Expected bytes length: ${expectedPayload.length}");
  debugPrint("Keys match: ${_compareBytes(publicKeyBytes, expectedPayload)}");
}


bool _compareBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
  // In AdbKeyManager after restoring keys
Future<void> _testSignature() async {
  if (_keyPair == null || _crypto == null) return;
  
  // Test signing with a known token
  final testToken = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
  final signature = _crypto!.signAdbTokenPayload(testToken);
  
  debugPrint("Test signature length: ${signature.length}");
  debugPrint("Test signature: ${base64.encode(signature)}");
  
  // Verify with public key
  // Add verification logic here if flutter_adb exposes it
}

  Future<void> _generateNewKeypair() async {
    debugPrint("🔑 Generating NEW RSA keypair");
    await LogService.instance.log("🔑 Generating NEW RSA keypair");

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        _keyPair = AdbCrypto.generateAdbKeyPair();
        if (_keyPair == null ||
            _keyPair!.publicKey == null ||
            _keyPair!.privateKey == null) {
          debugPrint("Keypair generation returned null on attempt $attempt");
          continue;
        }

        _crypto = AdbCrypto(keyPair: _keyPair!);

        final pubPemRaw = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(_keyPair!.publicKey);
        final privPemRaw = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(_keyPair!.privateKey);

        if (pubPemRaw.isEmpty || privPemRaw.isEmpty) {
          debugPrint("Empty PEMs on attempt $attempt");
          continue;
        }

        final pubPem = _normalizePemNewlines(pubPemRaw);
        final privPem = _normalizePemNewlines(privPemRaw);

        // Persist to secure storage
        await _storage.write(key: privateKeyKey, value: privPem);
        await _storage.write(key: publicKeyKey, value: pubPem);

        // Verify
        final verifyPriv = await _storage.read(key: privateKeyKey);
        final verifyPub = await _storage.read(key: publicKeyKey);

        if (verifyPriv == privPem && verifyPub == pubPem) {
          _publicKeyPem = pubPem;
          _keyFingerprint = computeAndroidAdbFingerprint(pubPem);
          _keysAuthorized = false;
          await _storage.delete(key: keysAuthorizedKey);
          await _writePemsToFiles(privPem, pubPem);
          debugPrint("✅ NEW KEYS GENERATED & STORED: $_keyFingerprint");
          return;
        } else {
          debugPrint("❌ Storage verification failed - retrying...");
        }
      } catch (e, st) {
        debugPrint("Key generation failed (attempt $attempt): $e\n$st");
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    throw Exception('Failed to generate valid RSA keypair');
  }

  Future<void> markKeysAuthorized() async {
    try {
      if (_keyPair != null) {
        final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(_keyPair!.privateKey);
        final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(_keyPair!.publicKey);

        if (privPem.isNotEmpty && pubPem.isNotEmpty) {
          final normalizedPriv = _normalizePemNewlines(privPem);
          final normalizedPub = _normalizePemNewlines(pubPem);

          await _storage.write(key: privateKeyKey, value: normalizedPriv);
          await _storage.write(key: publicKeyKey, value: normalizedPub);
          await _storage.write(key: keysAuthorizedKey, value: 'true');
          await _writePemsToFiles(normalizedPriv, normalizedPub);

          _keysAuthorized = true;
          _publicKeyPem = normalizedPub;
          _keyFingerprint ??= computeAndroidAdbFingerprint(normalizedPub);

          debugPrint("💾 Keys re-saved post-connection: $_keyFingerprint");
        }
      }
    } catch (e, st) {
      debugPrint("Key save error: $e\n$st");
    }
  }

  Future<void> regenerateKeys() async {
    await _clearStoredKeys();
    await _generateNewKeypair();
    _keysAuthorized = false;
    _cryptoReady = _crypto != null;
  }

  Future<void> _clearStoredKeys() async {
    debugPrint("🗑️ Clearing stored crypto keys");
    await LogService.instance.log("🗑️ Clearing stored crypto keys");
    try {
      await _storage.delete(key: privateKeyKey);
      await _storage.delete(key: publicKeyKey);
      await _storage.delete(key: keysAuthorizedKey);
    } catch (_) {}
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/adb_private.pem').delete().catchError((_) {});
      await File('${dir.path}/adb_public.pem').delete().catchError((_) {});
    } catch (_) {}
    _keyFingerprint = null;
    _publicKeyPem = null;
    _crypto = null;
    _keyPair = null;
    _cryptoReady = false;
    _keysAuthorized = false;
  }

  Future<void> _writePemsToFiles(String privPem, String pubPem) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final privFile = File('${dir.path}/adb_private.pem');
      final pubFile = File('${dir.path}/adb_public.pem');
      await privFile.writeAsString(privPem, flush: true);
      await pubFile.writeAsString(pubPem, flush: true);
    } catch (e) {
      debugPrint("File write error: $e");
    }
  }

  String _normalizePemNewlines(String pem) {
    return pem
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  // Compute ADB/TV-compatible MD5 fingerprint from a PKCS#1 PEM public key
  String computeSshRsaMd5FingerprintFromPem(String pubPem) {
    try {
      // parse RSAPublicKey using basic_utils
      final pub = CryptoUtils.rsaPublicKeyFromPem(pubPem) as RSAPublicKey;
      final blob = _buildSshRsaBlob(pub);
      final digest = md5.convert(blob);
      final fingerprint = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
      return fingerprint;
    } catch (e, st) {
      debugPrint("Fingerprint compute error: $e\n$st");
      return "";
    }
  }

  // Helper utilities to build ssh-rsa blob
  Uint8List _writeUint32(int v) {
    return Uint8List.fromList([
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff
    ]);
  }

  Uint8List _bigIntToBytes(BigInt n) {
    if (n == BigInt.zero) return Uint8List.fromList([0]);
    var tmp = n;
    final bytes = <int>[];
    while (tmp > BigInt.zero) {
      bytes.insert(0, (tmp & BigInt.from(0xff)).toInt());
      tmp = tmp >> 8;
    }
    // if highest bit set, prefix with 0
    if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
      bytes.insert(0, 0);
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List _buildSshRsaBlob(RSAPublicKey pub) {
    final name = utf8.encode('ssh-rsa');
    final eBytes = _bigIntToBytes(pub.exponent!);
    final nBytes = _bigIntToBytes(pub.modulus!);

    final builder = BytesBuilder();
    builder.add(_writeUint32(name.length));
    builder.add(name);
    builder.add(_writeUint32(eBytes.length));
    builder.add(eBytes);
    builder.add(_writeUint32(nBytes.length));
    builder.add(nBytes);

    return builder.toBytes();
  }

  String computeAndroidAdbFingerprint(String pubPem) {
  try {
    final pub = CryptoUtils.rsaPublicKeyFromPem(pubPem) as RSAPublicKey;
    
    // Build Android's custom RSA public key structure
    final androidKeyBytes = AdbCrypto.convertRsaPublicKeyToAdbFormat(pub);
    
    // MD5 hash of the entire structure
    final digest = md5.convert(androidKeyBytes);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  } catch (e, st) {
    debugPrint("Android fingerprint error: $e\n$st");
    return "";
  }
}

// Uint8List _buildAndroidRsaPublicKey(RSAPublicKey pub) {
//   final modulus = pub.modulus!;
//   final exponent = pub.exponent!;
  
//   // Android uses 2048-bit keys = 256 bytes = 64 words
//   const keySize = 2048;
//   const keySizeBytes = keySize ~/ 8; // 256 bytes
//   const keySizeWords = keySizeBytes ~/ 4; // 64 words
  
//   // Get modulus bytes (little-endian for Android)
//   final modulusBytes = _bigIntToBytesLE(modulus, keySizeBytes);
  
//   // Calculate Montgomery parameters
//   final n0inv = _calculateN0Inv(modulus);
//   final rr = _calculateRR(modulus, keySizeBytes);
  
//   final builder = BytesBuilder();
  
//   // 1. modulus_size_words (4 bytes, little-endian)
//   builder.add(_uint32ToLE(keySizeWords));
  
//   // 2. n0inv (4 bytes, little-endian)
//   builder.add(_uint32ToLE(n0inv));
  
//   // 3. modulus (256 bytes, little-endian)
//   builder.add(modulusBytes);
  
//   // 4. rr (256 bytes, little-endian)
//   builder.add(rr);
  
//   // 5. exponent (4 bytes, little-endian)
//   builder.add(_uint32ToLE(exponent.toInt()));
  
//   return builder.toBytes();
// }

// In AdbKeyManager, replace _buildAndroidRsaPublicKey with:
Uint8List _buildAndroidRsaPublicKey(RSAPublicKey pub) {
  // Use flutter_adb's implementation directly
  return AdbCrypto.convertRsaPublicKeyToAdbFormat(pub);
}

// Convert BigInt to little-endian bytes with fixed length
Uint8List _bigIntToBytesLE(BigInt n, int length) {
  final bytes = Uint8List(length);
  var temp = n;
  for (int i = 0; i < length; i++) {
    bytes[i] = (temp & BigInt.from(0xff)).toInt();
    temp = temp >> 8;
  }
  return bytes;
}

// Convert uint32 to little-endian bytes
Uint8List _uint32ToLE(int value) {
  return Uint8List.fromList([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}

// Calculate n0inv: -1 / n[0] mod 2^32
int _calculateN0Inv(BigInt modulus) {
  final n0 = (modulus & BigInt.from(0xffffffff)).toInt();
  // Extended Euclidean algorithm for modular inverse
  int x = n0;
  int y = 1;
  for (int i = 0; i < 32; i++) {
    y = (y * (2 - x * y)) & 0xffffffff;
  }
  return (-y) & 0xffffffff;
}

// Calculate R^2 mod N (Montgomery parameter)
Uint8List _calculateRR(BigInt modulus, int length) {
  // R = 2^(key_size_bits) = 2^2048
  final r = BigInt.two.pow(length * 8);
  // R^2 mod N
  final rr = (r * r) % modulus;
  return _bigIntToBytesLE(rr, length);
}


  // ---------------------
  // PKCS#1 -> PKCS#8 conversion helper
  // ---------------------
  // Construct DER-encoded PKCS#8 structure that wraps a PKCS#1 private-key DER blob.
  // This avoids using asn1lib or lib-specific OID helpers to prevent version issues.
  Uint8List _wrapPkcs1DerIntoPkcs8Der(Uint8List pkcs1Der) {
    // OID bytes for rsaEncryption (1.2.840.113549.1.1.1)
    final oidContent = <int>[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01];
    final oid = <int>[0x06, oidContent.length] + oidContent; // OBJECT IDENTIFIER

    // NULL element for algorithm params
    final nullBytes = <int>[0x05, 0x00];

    // algorithmIdentifier = SEQUENCE { OID, NULL }
    final algIdContent = oid + nullBytes;
    final algId = <int>[0x30] + _encodeLength(algIdContent.length) + algIdContent;

    // privateKey octet string
    final privOctet = <int>[0x04] + _encodeLength(pkcs1Der.length) + pkcs1Der;

    // version = INTEGER 0
    final version = <int>[0x02, 0x01, 0x00];

    // top-level sequence content = version + algId + privOctet
    final topContent = version + algId + privOctet;
    final topSeq = <int>[0x30] + _encodeLength(topContent.length) + topContent;

    return Uint8List.fromList(topSeq);
  }

  // DER length encoder
  List<int> _encodeLength(int len) {
    if (len < 128) {
      return [len];
    } else {
      // long form
      final bytes = <int>[];
      var v = len;
      while (v > 0) {
        bytes.insert(0, v & 0xff);
        v >>= 8;
      }
      final lengthOfLength = bytes.length;
      return [0x80 | lengthOfLength] + bytes;
    }
  }

  // Convert a PKCS#1 PEM string to a PKCS#8 PEM string
  String _convertPkcs1PemToPkcs8Pem(String pkcs1Pem) {
    // extract base64 body
    final body = pkcs1Pem
        .split(RegExp(r'\r?\n'))
        .where((line) =>
            line.trim().isNotEmpty &&
            !line.contains('BEGIN') &&
            !line.contains('END'))
        .join('');
    final pkcs1Der = base64.decode(body);

    final pkcs8Der = _wrapPkcs1DerIntoPkcs8Der(Uint8List.fromList(pkcs1Der));
    final pkcs8Base64 = base64.encode(pkcs8Der);
    final chunked = pkcs8Base64.replaceAllMapped(RegExp('.{1,64}'), (m) => '${m.group(0)}\n');

    return '-----BEGIN PRIVATE KEY-----\n$chunked-----END PRIVATE KEY-----\n';
  }
}
