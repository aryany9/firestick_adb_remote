import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart'; // Add to pubspec.yaml: crypto: ^3.0.3
import 'dart:typed_data';

/// Compute Android ADB-style RSA fingerprint (MD5 of base64 public key)
String computeAdbFingerprint(RSAPublicKey publicKey) {
  try {
    // Export public key to PEM
    final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey);

    // Extract base64 portion (between BEGIN/END markers)
    final base64Match = RegExp(
      r'-----BEGIN RSA PUBLIC KEY-----\s*([A-Za-z0-9+/=\s]+)\s*-----END RSA PUBLIC KEY-----',
    ).firstMatch(pubPem);

    if (base64Match == null) {
      return 'INVALID_PEM';
    }

    // Clean base64 (remove whitespace/newlines)
    final base64Clean = base64Match.group(1)!.replaceAll(RegExp(r'\s'), '');

    // Decode base64 to raw bytes
    final publicKeyBytes = base64Decode(base64Clean);

    // Compute MD5 hash
    final md5Hash = md5.convert(publicKeyBytes);

    // Format as colon-separated uppercase hex (like Android shows)
    final fingerprint = md5Hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');

    return fingerprint;
  } catch (e) {
    debugPrint("Fingerprint computation failed: $e");
    return 'ERROR';
  }
}

String computeAdbFingerprintFromPem(String pubPem) {
  // Extract ADB-style base64 block from PEM
  final match = RegExp(
    r'-----BEGIN RSA PUBLIC KEY-----\s*([A-Za-z0-9+/=\s]+)\s*-----END RSA PUBLIC KEY-----',
  ).firstMatch(pubPem);
  if (match == null) return 'INVALID_PEM';

  final b64 = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  final keyBytes = base64Decode(b64);

  // Android uses MD5 over the public key blob
  final digest = md5.convert(keyBytes);
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}
