// AdbManager.dart (optimized for low latency)
// Drop-in replacement for your previous AdbManager. Keeps crypto code and high level behaviours.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/adb_connection.dart' show AdbConnection;
import 'package:flutter_adb/adb_stream.dart' show AdbStream;
import 'package:flutter_adb/adb_crypto.dart' show AdbCrypto;
import 'package:pointycastle/api.dart' as pc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

final _storage = FlutterSecureStorage();
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
  AdbStream? _shell; // hot shell
  StreamSubscription<bool>? _connSub;
  Timer? _keepAliveTimer;

  // crypto - KEEP THESE ACROSS DISCONNECT/RECONNECT
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _keyPair;
  AdbCrypto? _crypto;
  bool _cryptoReady = false;
  bool _keysAuthorized = false;

  // file-backed PEMs
  Future<Directory> _getAppDocDir() async =>
      await getApplicationDocumentsDirectory();

  Future<Map<String, String>?> _readPemsFromFiles() async {
    try {
      final dir = await _getAppDocDir();
      final privFile = File('${dir.path}/adb_private.pem');
      final pubFile = File('${dir.path}/adb_public.pem');
      if (await privFile.exists() && await pubFile.exists()) {
        final priv = await privFile.readAsString();
        final pub = await pubFile.readAsString();
        if (priv.trim().isNotEmpty && pub.trim().isNotEmpty) {
          return {'priv': priv, 'pub': pub};
        }
      }
    } catch (e) {}
    return null;
  }

  Future<void> _writePemsToFiles(String privPem, String pubPem) async {
    try {
      final dir = await _getAppDocDir();
      final privFile = File('${dir.path}/adb_private.pem');
      final pubFile = File('${dir.path}/adb_public.pem');
      await privFile.writeAsString(privPem, flush: true);
      await pubFile.writeAsString(pubPem, flush: true);
    } catch (e) {}
  }

  // queue to serialize shell writes; optimized for immediate writes
  final Queue<_QueuedWrite> _writeQueue = Queue();
  bool _processingQueue = false;
  bool _connectBusy = false;

  // command coalescing / repeat acceleration
  String? _lastCommandSent;
  DateTime? _lastCommandTime;
  int _repeatAccelerationStep = 0;

  // repeat helper
  Timer? _repeatTimer;
  String? _repeatCommand; // the command being repeated
  Duration _repeatInitialDelay = const Duration(milliseconds: 300);
  Duration _repeatFastInterval = const Duration(milliseconds: 90);

  AdbManager() {
    _init();
  }

  Future<void> _init() async {
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

    notifyListeners();
  }

  Future<void> _restoreCrypto() async {
    Map<String, String>? filePems;
    try {
      filePems = await _readPemsFromFiles();
    } catch (_) {
      filePems = null;
    }

    final privPem = filePems != null
        ? filePems['priv']
        : await _storage.read(key: _privateKeyKey);
    final pubPem = filePems != null
        ? filePems['pub']
        : await _storage.read(key: _publicKeyKey);

    try {
      if (privPem != null &&
          privPem.trim().isNotEmpty &&
          pubPem != null &&
          pubPem.trim().isNotEmpty) {
        if (!privPem.contains('BEGIN RSA PRIVATE KEY') ||
            !pubPem.contains('BEGIN RSA PUBLIC KEY')) {
          await _clearStoredKeys();
          await _generateNewKeypair();
          return;
        }
        final rsaPrivate =
            CryptoUtils.rsaPrivateKeyFromPem(privPem) as RSAPrivateKey;
        final rsaPublic =
            CryptoUtils.rsaPublicKeyFromPem(pubPem) as RSAPublicKey;
        if (rsaPrivate.modulus == null || rsaPublic.modulus == null) {
          await _clearStoredKeys();
          await _generateNewKeypair();
        } else {
          _keyPair = AsymmetricKeyPair(rsaPublic, rsaPrivate);
          _crypto = AdbCrypto(keyPair: _keyPair!);
        }
      } else {
        await _generateNewKeypair();
      }
    } catch (e) {
      await _clearStoredKeys();
      await _generateNewKeypair();
    } finally {
      _cryptoReady = true;
      notifyListeners();
    }
  }

  Future<void> _clearStoredKeys() async {
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
  }

  Future<void> _generateNewKeypair() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      _keyPair = AdbCrypto.generateAdbKeyPair();
      if (_keyPair != null &&
          _keyPair!.privateKey != null &&
          _keyPair!.publicKey != null) {
        try {
          final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(
            _keyPair!.privateKey,
          );
          final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(
            _keyPair!.publicKey,
          );
          if (privPem.trim().isNotEmpty && pubPem.trim().isNotEmpty) {
            _crypto = AdbCrypto(keyPair: _keyPair!);
            await _storage.write(key: _privateKeyKey, value: privPem);
            await _storage.write(key: _publicKeyKey, value: pubPem);
            await _writePemsToFiles(privPem, pubPem);
            _keysAuthorized = false;
            await _storage.delete(key: _keysAuthorizedKey);
            return;
          }
        } catch (e) {}
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    throw Exception('Failed to generate valid RSA keypair after 3 attempts');
  }

  Future<void> _openShell() async {
    if (_connection == null) return;
    // If a hot shell already exists and seems alive, keep it.
    if (_shell != null) return;

    try {
      _shell = await _connection!.openShell();
      _shell!.onPayload.listen(
        (_) {
          // intentionally ignore payload. We're sending one-way commands.
        },
        onError: (e) {
          _shell = null;
        },
        onDone: () {
          _shell = null;
        },
      );
    } catch (e) {
      _shell = null;
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    // Keepalive every 30s while sleeping - send a tiny no-op that doesn't flood shell
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      if (connectionState == ConnectionState.sleeping && _connection != null) {
        try {
          // Lightweight: write a newline to shell to keep the underlying TCP/AOSP connection alive.
          // This uses the existing hot-shell write path (non-blocking).
          _tryImmediateWrite(Uint8List.fromList(utf8.encode('\n')));
        } catch (e) {
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
    if (savedIp != null) {
      await connect(host: savedIp, p: savedPort);
    }
  }

  Future<void> connect({String? host, int? p}) async {
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
        connectionState = ConnectionState.disconnected;
        await _cleanupConnection();
        return;
      }

      await _openShell();
      connectionState = ConnectionState.connected;

      // Save key PEMs and mark as authorized
      try {
        final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(
          _keyPair!.privateKey,
        );
        final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(
          _keyPair!.publicKey,
        );
        await _storage.write(key: _privateKeyKey, value: privPem);
        await _storage.write(key: _publicKeyKey, value: pubPem);
        await _storage.write(key: _keysAuthorizedKey, value: 'true');
        await _writePemsToFiles(privPem, pubPem);
        _keysAuthorized = true;
      } catch (e) {}

      await _storage.write(key: _lastIpKey, value: effectiveHost);
      await _storage.write(key: _lastPortKey, value: effectivePort.toString());

      ip = effectiveHost;
      port = effectivePort;
    } catch (e) {
      await _cleanupConnection();
    } finally {
      _connectBusy = false;
      notifyListeners();
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
    if (connecting) {
      await Future.delayed(const Duration(milliseconds: 150));
    }

    try {
      _shell?.sendClose();
    } catch (e) {}
    _shell = null;

    try {
      await _connSub?.cancel();
    } catch (e) {}
    _connSub = null;

    try {
      await _connection?.disconnect();
    } catch (e) {}
    _connection = null;

    _writeQueue.clear();
    _processingQueue = false;
    connectionState = ConnectionState.disconnected;
    notifyListeners();
  }

  /// FAST path: attempt to write directly to shell when queue empty.
  /// This avoids the queue overhead for single-tap interactions.
  Future<bool> _tryImmediateWrite(Uint8List bytes) async {
    if (_connection == null) return false;
    if (connectionState == ConnectionState.sleeping) {
      // wake minimally (ensure shell active) without full reconnect
      await wake();
    }

    if (_shell == null) {
      await _openShell();
      if (_shell == null) return false;
    }

    try {
      // Try non-blocking write first
      final ok = await _shell!.write(bytes, false);
      if (ok) {
        // update command history for acceleration heuristics
        _updateLastCommand(bytes);
        return true;
      } else {
        // fallback attempt (blocking)
        final ok2 = await _shell!.write(bytes, true);
        if (ok2) {
          _updateLastCommand(bytes);
        }
        return ok2;
      }
    } catch (e) {
      // if immediate write fails, don't throw — allow queue fallback
      return false;
    }
  }

  void _updateLastCommand(Uint8List bytes) {
    try {
      final s = utf8.decode(bytes).trim();
      if (s.isNotEmpty) {
        _lastCommandSent = s;
        _lastCommandTime = DateTime.now();
      }
    } catch (_) {}
  }

  /// Enqueue write and ensure the queue is being processed.
  Future<bool> sendShellCommand(String cmd) async {
    if (_connection == null) return false;

    if (connectionState == ConnectionState.sleeping) {
      // wake quickly for active usage
      await wake();
    }

    if (_shell == null) await _openShell();

    final bytes = Uint8List.fromList(utf8.encode('$cmd\n'));

    // Acceleration / coalescing hint:
    // If the same command occurred very recently, accelerate by avoiding extra queue wait.
    final now = DateTime.now();
    if (_writeQueue.isEmpty) {
      final immediateOk = await _tryImmediateWrite(bytes);
      if (immediateOk) return true;
    }

    // Otherwise push to queue (queue processor will very quickly drain it)
    final item = _QueuedWrite(bytes);
    _writeQueue.add(item);
    _processQueue(); // don't await
    return item.completer.future;
  }

  Future<void> _processQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;
    while (_writeQueue.isNotEmpty) {
      final item = _writeQueue.removeFirst();
      bool ok = false;
      try {
        if (_shell == null) {
          // attempt to re-open shell once
          await _openShell();
        }
        if (_shell != null) {
          try {
            ok = await _shell!.write(item.bytes, false);
            if (!ok) {
              // one immediate retry
              ok = await _shell!.write(item.bytes, true);
            }
          } catch (e) {
            // final retry
            try {
              ok = await _shell!.write(item.bytes, true);
            } catch (e2) {
              ok = false;
            }
          }
        } else {
          ok = false;
        }
      } catch (e) {
        ok = false;
      }

      if (!item.completer.isCompleted) item.completer.complete(ok);

      // tiny microtask yield — avoids starving event loop without adding ms-level delay
      await Future.microtask(() {});
    }
    _processingQueue = false;
  }

  // --- Repeat / hold helpers ---

  /// Start repeating a shell command (use this for onLongPressStart)
  void startRepeat(
    String cmd, {
    Duration initialDelay = const Duration(milliseconds: 300),
    Duration repeatInterval = const Duration(milliseconds: 120),
  }) {
    stopRepeat();
    _repeatCommand = cmd;
    _repeatInitialDelay = initialDelay;
    _repeatFastInterval = repeatInterval;
    _repeatTimer = Timer(_repeatInitialDelay, () async {
      // first repeated tick
      await sendShellCommand(cmd);
      // subsequent ticks faster
      _repeatTimer = Timer.periodic(_repeatFastInterval, (_) {
        sendShellCommand(cmd);
      });
    });
  }

  /// Stop repeating (use this for onLongPressEnd / onLongPressCancel)
  void stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatCommand = null;
  }

  // --- Convenience key helpers (same API as before) ---

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
    // If repeated same key pressed, accelerate slightly by bypassing queue when possible.
    final cmd = 'input keyevent $keycode';
    final now = DateTime.now();
    if (_lastCommandSent == cmd && _lastCommandTime != null) {
      final delta = now.difference(_lastCommandTime!);
      if (delta.inMilliseconds < 200) {
        // Fire immediate write if possible (this gives fastest feel)
        final immediateOk = await _tryImmediateWrite(
          Uint8List.fromList(utf8.encode('$cmd\n')),
        );
        if (immediateOk) return true;
      }
    }
    // default enqueue path
    return sendShellCommand(cmd);
  }

  Future<void> _cleanupConnection({bool preserveCrypto = true}) async {
    try {
      await _connSub?.cancel();
    } catch (_) {}
    _connSub = null;

    try {
      _shell?.sendClose();
    } catch (_) {}
    _shell = null;

    try {
      await _connection?.disconnect();
    } catch (_) {}
    _connection = null;

    connectionState = ConnectionState.disconnected;
    notifyListeners();
  }

  Future<void> regenerateKeys() async {
    await _clearStoredKeys();
    await _generateNewKeypair();
    _keysAuthorized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopKeepAlive();
    disconnect();
    super.dispose();
  }
}
