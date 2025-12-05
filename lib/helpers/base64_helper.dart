import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart';

const _base64Regex = r'^[A-Za-z0-9+/]*={0,2}$';

bool _isValidBase64(String? str) {
  if (str == null || str.isEmpty) return false;
  return RegExp(_base64Regex).hasMatch(str);
}

String _keyToBase64(RSAPublicKey key) {
  final bytes = _rsaToDerBytes(key);
  return base64Encode(bytes);
}

RSAPublicKey _base64ToRsaPublic(String b64) {
  final bytes = base64Decode(b64);
  final pem = utf8.decode(bytes); // Reconstruct if stored as PEM bytes
  return CryptoUtils.rsaPublicKeyFromPem(pem);
}

// Convert RSA key → binary DER → base64 (storage-safe)
Uint8List _rsaToDerBytes(RSAPublicKey key) {
  final encoder = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(key);
  // For now use PEM→DER conversion, but ideally direct DER
  return Uint8List.fromList(utf8.encode(encoder));
}
