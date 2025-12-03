// AdbManager.dart
// Enhanced version with Sleep/Wake mode to avoid re-authorization prompts
// Key features:
// - Sleep mode keeps connection alive but idle (no re-authorization needed)
// - Wake mode resumes activity on existing connection
// - Full disconnect only when explicitly needed
// - Automatic reconnection with keep-alive pings

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
  _QueuedWrite(this.bytes) : completer = Completer<bool>();
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  sleeping,
}

class AdbManager extends ChangeNotifier {
  // public state
  String? ip;
  int port = defaultPort;
  ConnectionState connectionState = ConnectionState.disconnected;
  
  // Convenience getters
  bool get connected => connectionState == ConnectionState.connected;
  bool get connecting => connectionState == ConnectionState.connecting;
  bool get sleeping => connectionState == ConnectionState.sleeping;
  bool get isActive => connectionState == ConnectionState.connected || 
                       connectionState == ConnectionState.sleeping;

  // internals
  AdbConnection? _connection;
  AdbStream? _shell;
  StreamSubscription<bool>? _connSub;
  Timer? _keepAliveTimer;

  // crypto - KEEP THESE ACROSS DISCONNECT/RECONNECT
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _keyPair;
  AdbCrypto? _crypto;
  bool _cryptoReady = false;
  bool _keysAuthorized = false;

  // File-backed PEM paths
  Future<Directory> _getAppDocDir() async => await getApplicationDocumentsDirectory();

  Future<Map<String, String>?> _readPemsFromFiles() async {
    try {
      final dir = await _getAppDocDir();
      final privFile = File('${dir.path}/adb_private.pem');
      final pubFile = File('${dir.path}/adb_public.pem');
      if (await privFile.exists() && await pubFile.exists()) {
        final priv = await privFile.readAsString();
        final pub = await pubFile.readAsString();
        if (priv.trim().isNotEmpty && pub.trim().isNotEmpty) {
          debugPrint('Found PEM files in ${dir.path} (priv=${priv.length}, pub=${pub.length})');
          return {'priv': priv, 'pub': pub};
        }
      }
    } catch (e) {
      debugPrint('Error reading PEM files: $e');
    }
    return null;
  }

  Future<void> _writePemsToFiles(String privPem, String pubPem) async {
    try {
      final dir = await _getAppDocDir();
      final privFile = File('${dir.path}/adb_private.pem');
      final pubFile = File('${dir.path}/adb_public.pem');
      await privFile.writeAsString(privPem, flush: true);
      await pubFile.writeAsString(pubPem, flush: true);
      debugPrint('Wrote PEM files to ${dir.path} (sizes: priv=${privPem.length}, pub=${pubPem.length})');
    } catch (e) {
      debugPrint('Failed to write PEM files: $e');
    }
  }

  // queue to serialize shell writes
  final Queue<_QueuedWrite> _writeQueue = Queue();
  bool _processingQueue = false;

  // prevents overlapping connect() attempts
  bool _connectBusy = false;

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

    final privPem = filePems != null ? filePems['priv'] : await _storage.read(key: _privateKeyKey);
    final pubPem = filePems != null ? filePems['pub'] : await _storage.read(key: _publicKeyKey);
    
    try {
      if (privPem != null &&
          privPem.trim().isNotEmpty &&
          pubPem != null &&
          pubPem.trim().isNotEmpty) {
        debugPrint('Restoring PEMs — lengths: priv=${privPem.length}, pub=${pubPem.length}');
        
        if (!privPem.contains('BEGIN RSA PRIVATE KEY') || !pubPem.contains('BEGIN RSA PUBLIC KEY')) {
          debugPrint('PEM headers missing or incorrect → regenerating');
          await _clearStoredKeys();
          await _generateNewKeypair();
          return;
        }
        
        try {
          final rsaPrivate = CryptoUtils.rsaPrivateKeyFromPem(privPem) as RSAPrivateKey;
          final rsaPublic = CryptoUtils.rsaPublicKeyFromPem(pubPem) as RSAPublicKey;

          if (rsaPrivate.modulus == null || rsaPublic.modulus == null) {
            debugPrint('Restored keys have invalid modulus → regenerating');
            await _clearStoredKeys();
            await _generateNewKeypair();
          } else {
            _keyPair = AsymmetricKeyPair(rsaPublic, rsaPrivate);
            _crypto = AdbCrypto(keyPair: _keyPair!);
            debugPrint('Successfully restored RSA keypair from storage');
          }
        } catch (parseError, stack) {
          debugPrint('Failed to parse stored PEM keys: $parseError');
          
          try {
            final privNorm = privPem.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
            final pubNorm = pubPem.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
            
            if (!privNorm.contains('BEGIN RSA PRIVATE KEY') || !pubNorm.contains('BEGIN RSA PUBLIC KEY')) {
              throw Exception('Normalized PEMs still invalid');
            }
            
            final rsaPrivate2 = CryptoUtils.rsaPrivateKeyFromPem(privNorm) as RSAPrivateKey;
            final rsaPublic2 = CryptoUtils.rsaPublicKeyFromPem(pubNorm) as RSAPublicKey;
            
            if (rsaPrivate2.modulus != null && rsaPublic2.modulus != null) {
              _keyPair = AsymmetricKeyPair(rsaPublic2, rsaPrivate2);
              _crypto = AdbCrypto(keyPair: _keyPair!);
              debugPrint('Parsed PEMs successfully after normalization');
            } else {
              throw Exception('Normalized keys invalid');
            }
          } catch (e2) {
            debugPrint('Normalization parse attempt failed: $e2');
            await _clearStoredKeys();
            await _generateNewKeypair();
          }
        }
      } else {
        debugPrint('Stored PEMs missing or empty → generating new keypair');
        await _generateNewKeypair();
      }
    } catch (e) {
      debugPrint('Unexpected error in crypto restore: $e → regenerating');
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

  Future<void> _openShell() async {
    if (_connection == null) return;

    try {
      _shell?.sendClose();
    } catch (_) {}
    _shell = null;

    _writeQueue.clear();

    try {
      _shell = await _connection!.openShell();
      _shell!.onPayload.listen(
        (_) {},
        onError: (e) {
          debugPrint('Shell stream error: $e');
          _shell = null;
        },
        onDone: () {
          debugPrint('Shell stream closed by remote');
          _shell = null;
        },
      );
    } catch (e) {
      debugPrint('Failed to open shell: $e');
      _shell = null;
    }
  }

  Future<void> _generateNewKeypair() async {
    debugPrint('Generating new RSA keypair...');
    
    for (int attempt = 0; attempt < 3; attempt++) {
      _keyPair = AdbCrypto.generateAdbKeyPair();
      if (_keyPair != null &&
          _keyPair!.privateKey != null &&
          _keyPair!.publicKey != null) {
        try {
          final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(_keyPair!.privateKey);
          final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(_keyPair!.publicKey);

          if (privPem.trim().isNotEmpty && pubPem.trim().isNotEmpty) {
            _crypto = AdbCrypto(keyPair: _keyPair!);
            await _storage.write(key: _privateKeyKey, value: privPem);
            await _storage.write(key: _publicKeyKey, value: pubPem);

            final checkPriv = await _storage.read(key: _privateKeyKey);
            final checkPub = await _storage.read(key: _publicKeyKey);
            
            if (checkPriv != null && checkPriv.trim().isNotEmpty &&
                checkPub != null && checkPub.trim().isNotEmpty) {
              try {
                await _writePemsToFiles(privPem, pubPem);
              } catch (e) {
                debugPrint('Error writing PEM files after generation: $e');
              }
              
              _keysAuthorized = false;
              await _storage.delete(key: _keysAuthorizedKey);
              
              debugPrint('New RSA keypair generated and saved');
              return;
            } else {
              debugPrint('Saved PEMs are empty after write (attempt ${attempt + 1})');
            }
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

  /// Start keep-alive timer to maintain connection
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (connectionState == ConnectionState.sleeping && _connection != null) {
        try {
          // Send a lightweight command to keep connection alive
          debugPrint('Keep-alive ping...');
          // Simple command that doesn't do anything visible
          await sendShellCommand('echo keepalive > /dev/null');
        } catch (e) {
          debugPrint('Keep-alive failed: $e - attempting reconnect');
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
    
    debugPrint('Connection lost, attempting to reconnect...');
    final savedIp = ip;
    final savedPort = port;
    
    await _cleanupConnection(preserveCrypto: true);
    
    if (savedIp != null) {
      await connect(host: savedIp, p: savedPort);
    }
  }

  Future<void> connect({String? host, int? p}) async {
    if (!_cryptoReady) {
      debugPrint('Crypto not ready; waiting...');
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return !_cryptoReady;
      });
    }

    if (connecting) {
      debugPrint('Already connecting, ignoring duplicate request');
      return;
    }

    final effectiveHost = host ?? ip;
    final effectivePort = p ?? port;
    if (effectiveHost == null || effectiveHost.isEmpty) {
      debugPrint('No host provided for connect');
      return;
    }

    if (_connectBusy) return;
    _connectBusy = true;

    try {
      connectionState = ConnectionState.connecting;
      notifyListeners();

      if (_crypto == null) {
        if (_keyPair == null) {
          debugPrint('No keypair available; this should not happen');
          return;
        }
        _crypto = AdbCrypto(keyPair: _keyPair!);
      }

      debugPrint('Connecting to $effectiveHost:$effectivePort with ${_keysAuthorized ? "authorized" : "new/unauthorized"} keys');
      
      _connection = AdbConnection(effectiveHost, effectivePort, _crypto!);

      _connSub?.cancel();
      try {
        _connSub = _connection!.onConnectionChanged.listen((state) {
          if (!state && connectionState != ConnectionState.disconnected) {
            debugPrint('Connection state changed: disconnected');
            _handleConnectionLoss();
          }
          notifyListeners();
        });
      } catch (_) {}

      final ok = await _connection!.connect();
      if (!ok) {
        debugPrint('AdbConnection.connect() returned false');
        connectionState = ConnectionState.disconnected;
        await _cleanupConnection();
        return;
      }

      await _openShell();
      connectionState = ConnectionState.connected;

      debugPrint('Successful connection - ensuring keys are saved');
      try {
        final privPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(_keyPair!.privateKey);
        final pubPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(_keyPair!.publicKey);
        
        await _storage.write(key: _privateKeyKey, value: privPem);
        await _storage.write(key: _publicKeyKey, value: pubPem);
        await _storage.write(key: _keysAuthorizedKey, value: 'true');
        
        try {
          await _writePemsToFiles(privPem, pubPem);
        } catch (e) {
          debugPrint('Failed to write PEM files during connect: $e');
        }
        
        if (!_keysAuthorized) {
          _keysAuthorized = true;
          debugPrint('Keys marked as authorized for first time');
        } else {
          debugPrint('Keys re-confirmed as authorized');
        }
      } catch (e) {
        debugPrint('Failed to save authorized keys: $e');
      }

      await _storage.write(key: _lastIpKey, value: effectiveHost);
      await _storage.write(key: _lastPortKey, value: effectivePort.toString());

      ip = effectiveHost;
      port = effectivePort;
      
      debugPrint('Connected successfully!');
    } catch (e) {
      debugPrint('Connect failed: $e');
      await _cleanupConnection();
    } finally {
      _connectBusy = false;
      notifyListeners();
    }
  }

  /// Put connection to sleep - keeps connection alive but stops active usage
  /// This avoids re-authorization prompts on Fire TV
  Future<void> sleep() async {
    if (connectionState != ConnectionState.connected) {
      debugPrint('Cannot sleep - not connected');
      return;
    }

    debugPrint('Putting connection to sleep (keeping connection alive)...');
    connectionState = ConnectionState.sleeping;
    _startKeepAlive();
    notifyListeners();
  }

  /// Wake connection from sleep - resume active usage
  Future<void> wake() async {
    if (connectionState != ConnectionState.sleeping) {
      debugPrint('Cannot wake - not sleeping (current state: $connectionState)');
      return;
    }

    debugPrint('Waking connection...');
    
    // Check if connection is still valid
    if (_connection == null || _shell == null) {
      debugPrint('Connection lost during sleep, reconnecting...');
      await connect();
      return;
    }

    _stopKeepAlive();
    connectionState = ConnectionState.connected;
    debugPrint('Connection awake and ready');
    notifyListeners();
  }

  /// Full disconnect - closes connection completely
  /// Use sleep() instead if you want to avoid re-authorization
  Future<void> disconnect() async {
    debugPrint('Disconnecting completely...');
    
    _stopKeepAlive();
    
    if (connecting) {
      await Future.delayed(const Duration(milliseconds: 150));
    }

    try {
      if (_shell != null) {
        _shell!.sendClose();
      }
    } catch (e) {
      debugPrint('Error closing shell (ignored): $e');
    } finally {
      _shell = null;
    }

    try {
      await _connSub?.cancel();
    } catch (e) {
      debugPrint('Error cancelling connSub (ignored): $e');
    }
    _connSub = null;

    try {
      await _connection?.disconnect();
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('StreamSink is bound to a stream')) {
        debugPrint('Ignoring StreamSink bound error during disconnect');
      } else {
        debugPrint('Error disconnecting connection: $e');
      }
    }
    _connection = null;

    _writeQueue.clear();
    _processingQueue = false;

    connectionState = ConnectionState.disconnected;
    
    debugPrint('Disconnected completely (crypto preserved for reconnection)');
    
    notifyListeners();
  }

  Future<bool> sendShellCommand(String cmd) async {
    if (_connection == null) {
      debugPrint('sendShellCommand: no _connection');
      return false;
    }

    if (connectionState == ConnectionState.sleeping) {
      debugPrint('Connection is sleeping, waking up...');
      await wake();
    }

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
          ok = false;
        } else {
          try {
            ok = await _shell!.write(item.bytes, false);
          } catch (e) {
            try {
              await _shell!.write(item.bytes, true);
              ok = true;
            } catch (e2) {
              debugPrint('Shell write failed: $e / $e2');
              ok = false;
            }
          }
        }
      } catch (e) {
        debugPrint('Exception during queued shell write: $e');
        ok = false;
      }

      if (!item.completer.isCompleted) item.completer.complete(ok);
      await Future.delayed(const Duration(milliseconds: 8));
    }

    _processingQueue = false;
  }

  // Helper methods for common inputs
  Future<bool> volUp() => sendShellCommand('input keyevent KEYCODE_VOLUME_UP');
  Future<bool> volDown() => sendShellCommand('input keyevent KEYCODE_VOLUME_DOWN');
  Future<bool> mute() => sendShellCommand('input keyevent KEYCODE_VOLUME_MUTE');
  Future<bool> dpadUp() => sendShellCommand('input keyevent KEYCODE_DPAD_UP');
  Future<bool> dpadDown() => sendShellCommand('input keyevent KEYCODE_DPAD_DOWN');
  Future<bool> dpadLeft() => sendShellCommand('input keyevent KEYCODE_DPAD_LEFT');
  Future<bool> dpadRight() => sendShellCommand('input keyevent KEYCODE_DPAD_RIGHT');
  Future<bool> dpadCenter() => sendShellCommand('input keyevent KEYCODE_DPAD_CENTER');
  Future<bool> back() => sendShellCommand('input keyevent KEYCODE_BACK');
  Future<bool> home() => sendShellCommand('input keyevent KEYCODE_HOME');

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
    debugPrint('Force regenerating keys...');
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