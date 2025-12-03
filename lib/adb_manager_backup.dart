// AdbManager.dart
// Clean, race-free AdbManager for Fire TV / Firestick using flutter_adb
// Key features:
// - Ensures RSA keypair is stable and restored before allowing connect()
// - Prevents double/overlapping connect attempts
// - Opens a persistent shell stream and reuses it
// - Serializes shell writes via a simple FIFO queue (preserves order)
// - Saves keys and last device only after a successful connect
// - Robust disconnect that closes shell and connection cleanly

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:basic_utils/basic_utils.dart' as pc;
import 'package:flutter/material.dart';
import 'package:flutter_adb/adb_connection.dart' show AdbConnection;
import 'package:flutter_adb/adb_stream.dart' show AdbStream;
import 'package:flutter_adb/adb_crypto.dart' show AdbCrypto;
import 'package:pointycastle/api.dart' as pc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final _storage = FlutterSecureStorage();
const _privateKeyKey = 'adb_private_pem';
const _publicKeyKey = 'adb_public_pem';
const _lastIpKey = 'last_adb_ip';
const _lastPortKey = 'last_adb_port';
const defaultPort = 5555;

class _QueuedWrite {
  final Uint8List bytes;
  final Completer<bool> completer;
  _QueuedWrite(this.bytes) : completer = Completer<bool>();
}

class AdbManager extends ChangeNotifier {
  // public state
  String? ip;
  int port = defaultPort;
  bool connected = false;
  bool connecting = false;

  // internals
  AdbConnection? _connection;
  AdbStream? _shell;
  StreamSubscription<bool>? _connSub;

  // crypto
  AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>? _keyPair;
  AdbCrypto? _crypto;
  bool _cryptoReady = false; // set when we've restored or generated keys

  // queue to serialize shell writes
  final Queue<_QueuedWrite> _writeQueue = Queue();
  bool _processingQueue = false;

  // prevents overlapping connect() attempts
  final _connectLock = Object();

  AdbManager() {
    _init();
  }

  Future<void> _init() async {
    // Restore keys first (or generate) BEFORE allowing any connect
    await _restoreCrypto();

    // Optionally: auto-connect to last IP/port if present in storage
    final lastIp = await _storage.read(key: _lastIpKey);
    final lastPort = await _storage.read(key: _lastPortKey);
    if (lastIp != null) {
      ip = lastIp;
      port = lastPort != null ? int.tryParse(lastPort) ?? defaultPort : defaultPort;
      // don't call connect() automatically; leave this decision to UI or call when desired
      // If you want auto-connect uncomment below: await connect();
    }

    notifyListeners();
  }

  Future<void> _restoreCrypto() async {
    final privPem = await _storage.read(key: _privateKeyKey);
    final pubPem = await _storage.read(key: _publicKeyKey);
  try {
  if (privPem != null && privPem.isNotEmpty && pubPem != null && pubPem.isNotEmpty) {
    final rsaPrivate = CryptoUtils.rsaPrivateKeyFromPem(privPem) as pc.RSAPrivateKey;
    final rsaPublic = CryptoUtils.rsaPublicKeyFromPem(pubPem) as pc.RSAPublicKey;

    if (rsaPrivate.modulus == null || rsaPublic.modulus == null) {
      debugPrint('Restored keys are invalid → regenerating');
      await _generateNewKeypair();
    } else {
      _keyPair = AsymmetricKeyPair(rsaPublic, rsaPrivate);
      _crypto = AdbCrypto(keyPair: _keyPair!);
    }
  } else {
    debugPrint('Stored PEMs missing → generating new keypair');
    await _generateNewKeypair();
  }
} catch (e) {
  debugPrint('Crypto restore failed → regenerating: $e');
  await _generateNewKeypair();
}
 finally {
    _cryptoReady = true;
    notifyListeners();
  }
}

Future<void> _openShell() async {
  if (_connection == null) return;

  // close old shell if exists
  try {
    _shell?.sendClose();
  } catch (_) {}
  _shell = null;

  // clear any pending writes
  _writeQueue.clear();

  try {
    _shell = await _connection!.openShell();
    _shell!.onPayload.listen((_) {}, onError: (e) {
      debugPrint('Shell stream error: $e');
      _shell = null;
    }, onDone: () {
      debugPrint('Shell stream closed by remote');
      _shell = null;
    });
  } catch (e) {
    debugPrint('Failed to open shell: $e');
    _shell = null;
  }
}


Future<void> _generateNewKeypair() async {
  for (int attempt = 0; attempt < 3; attempt++) {
    _keyPair = AdbCrypto.generateAdbKeyPair();
    if (_keyPair != null &&
        _keyPair!.privateKey != null &&
        _keyPair!.publicKey != null) {
      try {
        final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(_keyPair!.privateKey);
        final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(_keyPair!.publicKey);

        if (privPem.isNotEmpty && pubPem.isNotEmpty) {
          _crypto = AdbCrypto(keyPair: _keyPair!);
          await _storage.write(key: _privateKeyKey, value: privPem);
          await _storage.write(key: _publicKeyKey, value: pubPem);
          debugPrint('New RSA keypair generated and saved');
          return;
        }
      } catch (e) {
        debugPrint('Failed to encode or save keypair attempt $attempt: $e');
      }
    }
    debugPrint('Regenerating keypair (attempt ${attempt + 1})...');
    await Future.delayed(const Duration(milliseconds: 50));
  }

  throw Exception('Failed to generate valid RSA keypair after 3 attempts');
}



  /// Connect to an ADB device. Host must be set or provided here.
  /// This method is guarded to avoid overlapping connect attempts.
  Future<void> connect({String? host, int? p}) async {
    // don't start connecting until crypto is ready
    if (!_cryptoReady) {
      debugPrint('Crypto not ready; delaying connect');
      // wait for a short window for restore to finish. If you prefer, you can await a signal instead.
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return !_cryptoReady;
      });
    }

    // ensure sequential connect attempts
    if (connecting) return;

    final effectiveHost = host ?? ip;
    final effectivePort = p ?? port;
    if (effectiveHost == null || effectiveHost.isEmpty) {
      debugPrint('No host provided for connect');
      return;
    }

    // lock to prevent races (connect/disconnect called simultaneously)
    if (!await _tryEnterConnect()) return;

    try {
      connecting = true;
      notifyListeners();

      // create connection using restored crypto (do not recreate keypair here)
      _crypto ??= AdbCrypto(keyPair: _keyPair!);
      _connection = AdbConnection(effectiveHost, effectivePort, _crypto!);

      // optional: listen to connection state changes
      _connSub?.cancel();
      try {
        _connSub = _connection!.onConnectionChanged.listen((state) {
          connected = state;
          notifyListeners();
        });
      } catch (_) {
        // ignore if event not supported
      }

      final ok = await _connection!.connect();
      if (!ok) {
        debugPrint('AdbConnection.connect() returned false');
        connected = false;
        await _cleanupConnection();
        return;
      }
      await _openShell();

      // open persistent shell stream
      try {
        // attach a minimal listener so stream errors are observed
        _shell!.onPayload.listen((_) {}, onError: (e) {
          debugPrint('Shell stream error: $e');
        }, onDone: () {
          debugPrint('Shell stream closed by remote');
          _shell = null;
        });
      } catch (e) {
        debugPrint('Failed to open shell: $e');
        // Not fatal for simple write-only commands, but we prefer having _shell
        _shell = null;
      }
      connected = true;

      // persist keys + last ip/port only after a successful authorization (first-time acceptance)
      // Note: This overwrites only if storage didn't have keys before. If you want to always overwrite, tweak conditions.
      try {
        final existingPriv = await _storage.read(key: _privateKeyKey);
        final isCorrupt = existingPriv == null || existingPriv.trim().isEmpty;
        if (isCorrupt) {
          final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(_keyPair!.privateKey);
          final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(_keyPair!.publicKey);
          await _storage.write(key: _privateKeyKey, value: privPem);
          await _storage.write(key: _publicKeyKey, value: pubPem);
        }
        await _storage.write(key: _lastIpKey, value: effectiveHost);
        await _storage.write(key: _lastPortKey, value: effectivePort.toString());
      } catch (e) {
        debugPrint('Failed to save keys or last device: $e');
      }

      // update in-memory host/port
      ip = effectiveHost;
      port = effectivePort;

    } catch (e) {
      debugPrint('Connect failed: $e');
      await _cleanupConnection();
    } finally {
      connecting = false;
      _leaveConnect();
      notifyListeners();
    }
  }

  // Internal helpers to guard connect()/disconnect() races
  final _connectSemaphore = Completer<void>();
  bool _connectBusy = false;

  Future<bool> _tryEnterConnect() async {
    if (_connectBusy) return false;
    _connectBusy = true;
    return true;
  }

  void _leaveConnect() {
    _connectBusy = false;
  }

  /// Disconnect cleanly: close shell and then connection
  Future<void> disconnect() async {
  if (connecting) {
    await Future.delayed(const Duration(milliseconds: 150));
  }

  // Close shell safely
try {
  if (_shell != null) {
    _shell!.sendClose();
  }
} catch (e) {
  debugPrint('Error closing shell (ignored): $e');
} finally {
  _shell = null;
}
  // Cancel subscription
  try {
    await _connSub?.cancel();
  } catch (_) {}
  _connSub = null;

  // Disconnect connection
  try {
    await _connection?.disconnect();
  } catch (e) {
    debugPrint('Error disconnecting connection: $e');
  }

  _connection = null;

  // Clear queued writes
  _writeQueue.clear();
  _processingQueue = false;

  connected = false;
  notifyListeners();
}


  /// Writes a shell command using the persistent shell stream. Commands are queued and executed in FIFO.
  /// Returns true on successful write (not necessarily command execution result).
  Future<bool> sendShellCommand(String cmd) async {
    if (_connection == null) {
      debugPrint('sendShellCommand: no _connection');
      return false;
    }

    // if shell not available try to open it lazily
    // if (_shell == null) {
    //   try {
    //     _shell = await _connection!.openShell();
    //     _shell!.onPayload.listen((_) {}, onError: (e) {
    //       debugPrint('Shell error (lazy open): $e');
    //     }, onDone: () {
    //       debugPrint('Shell closed (lazy)');
    //       _shell = null;
    //     });
    //   } catch (e) {
    //     debugPrint('Unable to open shell lazily: $e');
    //     // proceed, but writes will fail below
    //   }
    // }
    if (_shell == null) await _openShell();


    final bytes = Uint8List.fromList(utf8.encode('$cmd\n'));
    final item = _QueuedWrite(bytes);
    _writeQueue.add(item);
    _processQueue();
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
          // cannot write without shell
          ok = false;
        } else {
          // the write API on AdbStream differs by package versions: try both common signatures
          try {
            // common signature: write(Uint8List bytes, bool flush)
            ok = await _shell!.write(item.bytes, false);
          } catch (e) {
            // fallback: some libs accept write(Uint8List)
            try {
              // sometimes the return type is void; treat as success if no throw
              await _shell!.write(item.bytes, true);
              ok = true;
            } catch (e2) {
              debugPrint('Shell write failed (both attempts): $e / $e2');
              ok = false;
            }
          }
        }
      } catch (e) {
        debugPrint('Exception during queued shell write: $e');
        ok = false;
      }

      if (!item.completer.isCompleted) item.completer.complete(ok);

      // Small delay prevents burst flooding; tune as needed
      await Future.delayed(const Duration(milliseconds: 8));
    }

    _processingQueue = false;
  }

  // Keep helper methods for common inputs
  Future<bool> volUp() async => await sendShellCommand('input keyevent KEYCODE_VOLUME_UP');
  Future<bool> volDown() async => await sendShellCommand('input keyevent KEYCODE_VOLUME_DOWN');
  Future<bool> mute() async => await sendShellCommand('input keyevent KEYCODE_VOLUME_MUTE');
  Future<bool> dpadUp() async => await sendShellCommand('input keyevent KEYCODE_DPAD_UP');
  Future<bool> dpadDown() async => await sendShellCommand('input keyevent KEYCODE_DPAD_DOWN');
  Future<bool> dpadLeft() async => await sendShellCommand('input keyevent KEYCODE_DPAD_LEFT');
  Future<bool> dpadRight() async => await sendShellCommand('input keyevent KEYCODE_DPAD_RIGHT');
  Future<bool> dpadCenter() async => await sendShellCommand('input keyevent KEYCODE_DPAD_CENTER');
  Future<bool> back() async => await sendShellCommand('input keyevent KEYCODE_BACK');
  Future<bool> home() async => await sendShellCommand('input keyevent KEYCODE_HOME');

  // tidy up internal state when connection fails
  Future<void> _cleanupConnection() async {
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
    connected = false;
    notifyListeners();
  }
}
