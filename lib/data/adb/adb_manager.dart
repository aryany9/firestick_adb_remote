import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:firestick_adb_remote/data/adb/helper.dart';
import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/adb_connection.dart' show AdbConnection;
import 'package:flutter_adb/adb_stream.dart' show AdbStream;
import 'package:flutter_adb/adb_crypto.dart' show AdbCrypto;
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/asymmetric/api.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

final _storage = FlutterSecureStorage();

// Use ORIGINAL keys - they work fine with normalization
const _privateKeyKey = 'adb_private_pem';
const _publicKeyKey = 'adb_public_pem';
const _lastIpKey = 'last_adb_ip';
const _lastPortKey = 'last_adb_port';
const _keysAuthorizedKey = 'adb_keys_authorized';
const defaultPort = 5555;

class _QueuedWrite {
  final Uint8List bytes;
  final Completer<bool> completer;
  final DateTime enqueuedAt;
  _QueuedWrite(this.bytes)
    : completer = Completer<bool>(),
      enqueuedAt = DateTime.now();
}

enum ConnectionState { disconnected, connecting, connected, sleeping }

class AdbManager extends ChangeNotifier {
  // public state
  String? ip;
  int port = defaultPort;
  ConnectionState connectionState = ConnectionState.disconnected;

  bool get connected => connectionState == ConnectionState.connected;
  bool get connecting => connectionState == ConnectionState.connecting;
  bool get sleeping => connectionState == ConnectionState.sleeping;
  bool get isActive =>
      connectionState == ConnectionState.connected ||
      connectionState == ConnectionState.sleeping;

  // internals
  AdbConnection? _connection;
  AdbStream? _shell;
  StreamSubscription<bool>? _connSub;
  Timer? _keepAliveTimer;

  // crypto
  pc.AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _keyPair;
  AdbCrypto? _crypto;
  bool _cryptoReady = false;
  bool _keysAuthorized = false;
  String? _keyFingerprint;

  // queue + connection state
  final Queue<_QueuedWrite> _writeQueue = Queue();
  bool _processingQueue = false;
  bool _connectBusy = false;

  // repeat helpers
  Timer? _repeatTimer;
  String? _repeatCommand;
  Duration _repeatInitialDelay = const Duration(milliseconds: 300);
  Duration _repeatFastInterval = const Duration(milliseconds: 90);

  AdbManager() {
    _init();
  }

  Future<Directory> _getAppDocDir() async =>
      await getApplicationDocumentsDirectory();

  Future<void> _writePemsToFiles(String privPem, String pubPem) async {
    try {
      final dir = await _getAppDocDir();
      final privFile = File('${dir.path}/adb_private.pem');
      final pubFile = File('${dir.path}/adb_public.pem');
      await privFile.writeAsString(privPem, flush: true);
      await pubFile.writeAsString(pubPem, flush: true);
    } catch (e) {
      debugPrint("File write error: $e");
    }
  }

  Future<void> _clearStoredKeys() async {
    debugPrint("🗑️ Clearing stored crypto keys");
    await LogService.instance.log("🗑️ Clearing stored crypto keys");
    try {
      await _storage.delete(key: _privateKeyKey);
      await _storage.delete(key: _publicKeyKey);
      await _storage.delete(key: _keysAuthorizedKey);
    } catch (_) {}
    try {
      final dir = await _getAppDocDir();
      await File('${dir.path}/adb_private.pem').delete().catchError((_) {});
      await File('${dir.path}/adb_public.pem').delete().catchError((_) {});
    } catch (_) {}
    _keyFingerprint = null;
  }

  Future<void> _init() async {
    debugPrint("🔑 Initializing AdbManager");
    await LogService.instance.log("🔑 Initializing AdbManager");

    await _restoreCrypto();

    final authStatus = await _storage.read(key: _keysAuthorizedKey);
    _keysAuthorized = authStatus == 'true';

    final lastIp = await _storage.read(key: _lastIpKey);
    final lastPort = await _storage.read(key: _lastPortKey);
    if (lastIp != null) {
      ip = lastIp;
      port = lastPort != null
          ? int.tryParse(lastPort) ?? defaultPort
          : defaultPort;
    }

    debugPrint(
      "✅ AdbManager init: IP=$ip:$port, KeysAuth=$_keysAuthorized, Fingerprint=$_keyFingerprint",
    );
    await LogService.instance.log(
      "✅ AdbManager init: IP=$ip:$port, KeysAuth=$_keysAuthorized, Fingerprint=$_keyFingerprint",
    );
    notifyListeners();
  }

  // Future<void> _restoreCrypto() async {
  //   debugPrint("🔑 Restoring crypto keys from secure storage");

  //   final privPem = await _storage.read(key: _privateKeyKey);
  //   final pubPem = await _storage.read(key: _publicKeyKey);

  //   // Safe preview logging
  //   if (privPem != null && privPem.isNotEmpty) {
  //     final end = min(100, privPem.length);
  //     debugPrint("RAW privPem[0-100]: ${privPem.substring(0, end)}");
  //   } else {
  //     debugPrint("RAW privPem: <null or empty>");
  //   }

  //   if (pubPem != null && pubPem.isNotEmpty) {
  //     final end = min(100, pubPem.length);
  //     debugPrint("RAW pubPem[0-100]: ${pubPem.substring(0, end)}");
  //   } else {
  //     debugPrint("RAW pubPem: <null or empty>");
  //   }

  //   final hasPriv = privPem != null && privPem.trim().isNotEmpty;
  //   final hasPub = pubPem != null && pubPem.trim().isNotEmpty;

  //   // First install or nothing stored: generate once
  //   if (!hasPriv || !hasPub) {
  //     debugPrint("🚫 No stored keys → generating first pair");
  //     await _generateNewKeypair();
  //     _cryptoReady = true;
  //     notifyListeners();
  //     return;
  //   }

  //   // Lightweight sanity check
  //   if (!privPem!.contains('BEGIN RSA PRIVATE KEY') ||
  //       !pubPem!.contains('BEGIN RSA PUBLIC KEY')) {
  //     debugPrint("🚫 Unexpected PEM format → regenerating once");
  //     await _clearStoredKeys();
  //     await _generateNewKeypair();
  //     _cryptoReady = true;
  //     notifyListeners();
  //     return;
  //   }

  //   // Parse existing PEMs
  //   try {
  //     final rsaPrivate =
  //         CryptoUtils.rsaPrivateKeyFromPem(privPem.trim()) as RSAPrivateKey;
  //     final rsaPublic =
  //         CryptoUtils.rsaPublicKeyFromPem(pubPem.trim()) as RSAPublicKey;

  //     _keyPair = pc.AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
  //       rsaPublic,
  //       rsaPrivate,
  //     );
  //     _crypto = AdbCrypto(keyPair: _keyPair!);

  //     _keyFingerprint =
  //         pubPem.substring(0, min(20, pubPem.length)).replaceAll('\n', '') +
  //         '...';
  //     debugPrint("✅ RESTORED SUCCESS: Fingerprint=$_keyFingerprint");
  //   } catch (e, st) {
  //     debugPrint("💥 RESTORE PARSE FAILED: $e\n$st");
  //     // await _clearStoredKeys();
  //     // await _generateNewKeypair();
  //   }

  //   _cryptoReady = _crypto != null;
  //   notifyListeners();
  // }

  Future<void> _restoreCrypto() async {
    debugPrint("🔑 Restoring crypto keys from secure storage");

    final pubPem = await _storage.read(key: _publicKeyKey);
    debugPrint("RAW pubPem: ${pubPem?.length ?? 0} chars");

    // Always generate a fresh pair for AdbCrypto (no ASN1 parsing)
    _keyPair = AdbCrypto.generateAdbKeyPair();
    if (_keyPair == null) {
      await _generateNewKeypair();
      _cryptoReady = _crypto != null;
      notifyListeners();
      return;
    }
    _crypto = AdbCrypto(keyPair: _keyPair!);

    if (pubPem != null &&
        pubPem.contains('BEGIN RSA PUBLIC KEY') &&
        pubPem.contains('END RSA PUBLIC KEY')) {
      // Compute fingerprint from stored public PEM
      final normalizedPub = _normalizePemNewlines(pubPem);
      _keyFingerprint = computeAdbFingerprintFromPem(normalizedPub);
      debugPrint("✅ RESTORED fingerprint (for comparison): $_keyFingerprint");
    } else {
      debugPrint("ℹ️ No stored public PEM; new fingerprint will be used");
    }

    _cryptoReady = true;
    notifyListeners();
  }

  Future<void> _generateNewKeypair() async {
    debugPrint("🔑 Generating NEW RSA keypair");

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        _keyPair = AdbCrypto.generateAdbKeyPair();
        _crypto = AdbCrypto(keyPair: _keyPair!);

        final pubPemRaw = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(
          _keyPair!.publicKey as RSAPublicKey,
        );

        final pubPem = _normalizePemNewlines(pubPemRaw);
        await _storage.write(key: _publicKeyKey, value: pubPem);

        // Compute the fingerprint that the TV will show
        _keyFingerprint = computeAdbFingerprintFromPem(pubPem);
        debugPrint("✅ NEW KEYS GENERATED. TV fingerprint: $_keyFingerprint");

        if (_keyPair == null ||
            _keyPair!.privateKey == null ||
            _keyPair!.publicKey == null) {
          debugPrint("Keypair null on attempt $attempt");
          continue;
        }

        final privPemRaw = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(
          _keyPair!.privateKey as RSAPrivateKey,
        );

        if (privPemRaw.isEmpty || pubPemRaw.isEmpty) {
          debugPrint("Empty PEMs on attempt $attempt");
          continue;
        }

        final privPem = _normalizePemNewlines(privPemRaw);

        _crypto = AdbCrypto(keyPair: _keyPair!);

        await _storage.write(key: _privateKeyKey, value: privPem);
        await _storage.write(key: _publicKeyKey, value: pubPem);

        final verifyPriv = await _storage.read(key: _privateKeyKey);
        final verifyPub = await _storage.read(key: _publicKeyKey);

        if (verifyPriv == privPem && verifyPub == pubPem) {
          _keyFingerprint = computeAdbFingerprint(
            _keyPair!.publicKey as RSAPublicKey,
          );
          _keysAuthorized = false;
          await _storage.delete(key: _keysAuthorizedKey);
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

  String _normalizePemNewlines(String pem) {
    // Replace all newline variants with standard \n, trim, and ensure proper PEM structure
    return pem
        .replaceAll('\r\n', '\n') // Windows CRLF → LF
        .replaceAll('\r', '\n') // Mac CR → LF
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty) // Remove blank lines
        .join('\n');
  }

  // Future<void> _generateNewKeypair() async {
  //   debugPrint("🔑 Generating NEW RSA keypair");
  //   await LogService.instance.log("🔑 Generating NEW RSA keypair");

  //   for (int attempt = 0; attempt < 3; attempt++) {
  //     try {
  //       _keyPair = AdbCrypto.generateAdbKeyPair();
  //       if (_keyPair == null ||
  //           _keyPair!.privateKey == null ||
  //           _keyPair!.publicKey == null) {
  //         debugPrint("Keypair null on attempt $attempt");
  //         continue;
  //       }

  //       final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(
  //         _keyPair!.privateKey as RSAPrivateKey,
  //       );
  //       final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(
  //         _keyPair!.publicKey as RSAPublicKey,
  //       );

  //       if (privPem.isEmpty || pubPem.isEmpty) {
  //         debugPrint("Encoded PEMs empty on attempt $attempt");
  //         continue;
  //       }

  //       _crypto = AdbCrypto(keyPair: _keyPair!);

  //       // Persist and verify
  //       await _storage.write(key: _privateKeyKey, value: privPem);
  //       await _storage.write(key: _publicKeyKey, value: pubPem);

  //       final verifyPriv = await _storage.read(key: _privateKeyKey);
  //       final verifyPub = await _storage.read(key: _publicKeyKey);

  //       if (verifyPriv == privPem && verifyPub == pubPem) {
  //         _keyFingerprint =
  //             pubPem.substring(0, min(20, pubPem.length)).replaceAll('\n', '') +
  //             '...';
  //         _keysAuthorized = false;
  //         await _storage.delete(key: _keysAuthorizedKey);
  //         debugPrint("✅ NEW KEYS GENERATED & VERIFIED: $_keyFingerprint");
  //         return;
  //       } else {
  //         debugPrint("❌ Storage verification failed - retrying...");
  //       }
  //     } catch (e, st) {
  //       debugPrint("Key generation failed (attempt $attempt): $e\n$st");
  //     }

  //     await Future.delayed(const Duration(milliseconds: 100));
  //   }

  //   throw Exception('Failed to generate valid RSA keypair');
  // }

  Future<void> connect({String? host, int? p}) async {
    debugPrint(
      "🔌 Connect to $host:$p | CryptoReady: $_cryptoReady | Fingerprint: $_keyFingerprint",
    );
    await LogService.instance.log(
      "🔌 Connect: $host:$p | Ready: $_cryptoReady | FP: $_keyFingerprint",
    );

    // Wait until crypto is ready
    if (!_cryptoReady) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return !_cryptoReady;
      });
    }

    if (connecting) return;

    final effectiveHost = host ?? ip;
    final effectivePort = p ?? port;
    if (effectiveHost == null || effectiveHost.isEmpty) return;

    if (_connectBusy) return;
    _connectBusy = true;

    try {
      connectionState = ConnectionState.connecting;
      notifyListeners();

      if (_crypto == null) {
        if (_keyPair == null) return;
        _crypto = AdbCrypto(keyPair: _keyPair!);
      }

      _connection = AdbConnection(effectiveHost, effectivePort, _crypto!);

      _connSub?.cancel();
      try {
        _connSub = _connection!.onConnectionChanged.listen((state) {
          if (!state && connectionState != ConnectionState.disconnected) {
            _handleConnectionLoss();
          }
          notifyListeners();
        });
      } catch (_) {}

      final ok = await _connection!.connect();
      if (!ok) {
        debugPrint("❌ Connection failed");
        connectionState = ConnectionState.disconnected;
        await _cleanupConnection();
        return;
      }

      await _openShell();
      connectionState = ConnectionState.connected;

      // Safely persist keys and mark as authorized
      try {
        if (_keyPair != null) {
          final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(
            _keyPair!.privateKey as RSAPrivateKey,
          );
          final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(
            _keyPair!.publicKey as RSAPublicKey,
          );

          if (privPem.isNotEmpty && pubPem.isNotEmpty) {
            await _storage.write(key: _privateKeyKey, value: privPem);
            await _storage.write(key: _publicKeyKey, value: pubPem);
            await _storage.write(key: _keysAuthorizedKey, value: 'true');
            await _writePemsToFiles(privPem, pubPem);
            _keysAuthorized = true;
            debugPrint("💾 Keys re-saved post-connection: $_keyFingerprint");
          } else {
            debugPrint("⚠️ Skipping key overwrite: encoded PEMs are empty");
          }
        }
      } catch (e, st) {
        debugPrint("Key save error: $e\n$st");
      }

      await _storage.write(key: _lastIpKey, value: effectiveHost);
      await _storage.write(key: _lastPortKey, value: effectivePort.toString());

      ip = effectiveHost;
      port = effectivePort;
      debugPrint(
        "✅ Connected: $effectiveHost:$effectivePort | FP: $_keyFingerprint",
      );
      await LogService.instance.log(
        "✅ Connected: $effectiveHost:$effectivePort",
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint("Connect error: $e\n$st");
      await _cleanupConnection();
    } finally {
      _connectBusy = false;
      notifyListeners();
    }
  }

  Future<void> _openShell() async {
    if (_connection == null) return;
    if (_shell != null) return;

    try {
      _shell = await _connection!.openShell();
      _shell!.onPayload.listen(
        (_) {},
        onError: (e) => _shell = null,
        onDone: () => _shell = null,
      );
    } catch (e) {
      _shell = null;
    }
  }

  Future<void> sleep() async {
    if (connectionState != ConnectionState.connected) return;
    connectionState = ConnectionState.sleeping;
    _startKeepAlive();
    notifyListeners();
  }

  Future<void> wake() async {
    if (connectionState != ConnectionState.sleeping) return;
    if (_connection == null || _shell == null) {
      await connect();
      return;
    }
    _stopKeepAlive();
    connectionState = ConnectionState.connected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _stopKeepAlive();
    _shell?.sendClose();
    _shell = null;
    _connSub?.cancel();
    _connSub = null;
    _connection?.disconnect();
    _connection = null;
    _writeQueue.clear();
    _processingQueue = false;
    connectionState = ConnectionState.disconnected;
    notifyListeners();
  }

  Future<bool> sendShellCommand(String cmd) async {
    if (_connection == null) return false;
    if (connectionState == ConnectionState.sleeping) await wake();
    if (_shell == null) await _openShell();

    final bytes = Uint8List.fromList(utf8.encode('$cmd\n'));
    if (_writeQueue.isEmpty) {
      final ok = await _tryImmediateWrite(bytes);
      if (ok) return true;
    }

    final item = _QueuedWrite(bytes);
    _writeQueue.add(item);
    _processQueue();
    return item.completer.future;
  }

  Future<bool> _tryImmediateWrite(Uint8List bytes) async {
    if (_connection == null || _shell == null) return false;
    try {
      final ok = await _shell!.write(bytes, false);
      if (ok) return true;
      return await _shell!.write(bytes, true);
    } catch (_) {
      return false;
    }
  }

  Future<void> _processQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;
    while (_writeQueue.isNotEmpty) {
      final item = _writeQueue.removeFirst();
      bool ok = false;
      try {
        if (_shell == null) await _openShell();
        if (_shell != null) {
          ok = await _shell!.write(item.bytes, false);
          if (!ok) ok = await _shell!.write(item.bytes, true);
        }
      } catch (_) {}
      if (!item.completer.isCompleted) item.completer.complete(ok);
      await Future.microtask(() {});
    }
    _processingQueue = false;
  }

  // Key helpers
  Future<bool> volUp() => sendShellCommand('input keyevent KEYCODE_VOLUME_UP');
  Future<bool> volDown() =>
      sendShellCommand('input keyevent KEYCODE_VOLUME_DOWN');
  Future<bool> mute() => sendShellCommand('input keyevent KEYCODE_VOLUME_MUTE');
  Future<bool> dpadUp() => _sendDpad('KEYCODE_DPAD_UP');
  Future<bool> dpadDown() => _sendDpad('KEYCODE_DPAD_DOWN');
  Future<bool> dpadLeft() => _sendDpad('KEYCODE_DPAD_LEFT');
  Future<bool> dpadRight() => _sendDpad('KEYCODE_DPAD_RIGHT');
  Future<bool> dpadCenter() => _sendDpad('KEYCODE_DPAD_CENTER');
  Future<bool> back() => sendShellCommand('input keyevent KEYCODE_BACK');
  Future<bool> home() => sendShellCommand('input keyevent KEYCODE_HOME');
  Future<bool> menu() => sendShellCommand('input keyevent KEYCODE_MENU');

  Future<bool> _sendDpad(String keycode) async {
    final cmd = 'input keyevent $keycode';
    return sendShellCommand(cmd);
  }

  void startRepeat(
    String cmd, {
    Duration initialDelay = const Duration(milliseconds: 300),
    Duration repeatInterval = const Duration(milliseconds: 120),
  }) {
    stopRepeat();
    _repeatCommand = cmd;
    _repeatTimer = Timer(initialDelay, () async {
      await sendShellCommand(cmd);
      _repeatTimer = Timer.periodic(
        repeatInterval,
        (_) => sendShellCommand(cmd),
      );
    });
  }

  void stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatCommand = null;
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      if (connectionState == ConnectionState.sleeping && _connection != null) {
        try {
          _tryImmediateWrite(Uint8List.fromList(utf8.encode('\n')));
        } catch (_) {
          await _handleConnectionLoss();
        }
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<void> _handleConnectionLoss() async {
    if (connectionState == ConnectionState.disconnected) return;
    final savedIp = ip;
    final savedPort = port;
    await _cleanupConnection(preserveCrypto: true);
    if (savedIp != null) await connect(host: savedIp, p: savedPort);
  }

  Future<void> _cleanupConnection({bool preserveCrypto = true}) async {
    _connSub?.cancel();
    _connSub = null;
    _shell?.sendClose();
    _shell = null;
    _connection?.disconnect();
    _connection = null;
    connectionState = ConnectionState.disconnected;
    notifyListeners();
  }

  Future<void> regenerateKeys() async {
    await _clearStoredKeys();
    await _generateNewKeypair();
    _keysAuthorized = false;
    _cryptoReady = _crypto != null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopKeepAlive();
    disconnect();
    super.dispose();
  }
}
