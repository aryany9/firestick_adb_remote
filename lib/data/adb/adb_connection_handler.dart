import 'dart:async';
import 'dart:math';

import 'package:firestick_adb_remote/data/adb/adb_key_manager.dart';
import 'package:firestick_adb_remote/data/adb/adb_shell_queue.dart';
import 'package:firestick_adb_remote/data/adb/constants.dart';
import 'package:firestick_adb_remote/data/adb/models/connection_state.dart';
import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AdbConnectionHandler {
  final FlutterSecureStorage _storage;
  final AdbKeyManager keyManager;
  final AdbShellQueue shellQueue;
  final VoidCallback onStateChanged;

  AdbConnection? _connection;
  StreamSubscription<bool>? _connSub;
  Timer? _keepAliveTimer;
  bool _connectBusy = false;
  bool _disconnectBusy = false;

  String? ip;
  int port = defaultPort;
  ConnectionState connectionState = ConnectionState.disconnected;

  AdbConnectionHandler({
    required FlutterSecureStorage storage,
    required this.keyManager,
    required this.shellQueue,
    required this.onStateChanged,
  }) : _storage = storage;

  bool get connected => connectionState.isConnected;
  bool get connecting => connectionState.isConnecting;
  bool get sleeping => connectionState.isSleeping;
  bool get isActive => connectionState.isActive;

  Future<void> initialize() async {
    final lastIp = await _storage.read(key: lastIpKey);
    final lastPort = await _storage.read(key: lastPortKey);
    if (lastIp != null) {
      ip = lastIp;
      port = lastPort != null ? int.tryParse(lastPort) ?? defaultPort : defaultPort;
    }
  }

  String? _computeActualAdbFingerprint() {
    try {
      final pubPem = keyManager.getPublicKeyPem();
      if (pubPem == null || pubPem.isEmpty) return null;
      final fingerprint = keyManager.computeAndroidAdbFingerprint(pubPem);
      return fingerprint;
    } catch (e, st) {
      debugPrint("❌ Fingerprint computation error: $e\n$st");
      return null;
    }
  }

  Future<void> connect({String? host, int? p}) async {
    debugPrint("🔌 Connect to $host:$p | CryptoReady: ${keyManager.cryptoReady}");
    await LogService.instance.log("🔌 Connect: $host:$p");

    if (!keyManager.cryptoReady) {
      await Future.doWhile(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        return !keyManager.cryptoReady;
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
      onStateChanged();

      if (keyManager.crypto == null) {
        debugPrint("No crypto available; aborting connect");
        connectionState = ConnectionState.disconnected;
        onStateChanged();
        return;
      }

      // ✅ KEY FIX: Reuse existing connection if available and for same host/port
      if (_connection != null) {
        // Check if we can reuse the existing connection
        final sameHost = _connection!.ip == effectiveHost;
        final samePort = _connection!.port == effectivePort;
        
        if (sameHost && samePort) {
          debugPrint('🔁 Reusing existing AdbConnection instance (session maintained)');
          
          // Try to reconnect with existing instance
          try {
            final ok = await _connection!.connect();
            if (ok) {
              await shellQueue.openShell(_connection!);
              connectionState = ConnectionState.connected;
              
              await _storage.write(key: lastIpKey, value: effectiveHost);
              await _storage.write(key: lastPortKey, value: effectivePort.toString());
              
              ip = effectiveHost;
              port = effectivePort;
              debugPrint("✅ Reconnected using existing session: $effectiveHost:$effectivePort");
              await LogService.instance.log("✅ Reconnected (no auth required): $effectiveHost:$effectivePort");
              onStateChanged();
              return;
            } else {
              debugPrint("⚠️ Reconnect failed with existing instance, creating new");
            }
          } catch (e) {
            debugPrint("⚠️ Error reusing connection: $e");
          }
        }
      }

      // Diagnostic logging
      final payload = keyManager.getAdbPublicKeyBase64Payload();
      if (payload != null) {
        debugPrint('🔎 ADB PublicKey payload (len=${payload.length}): ${payload.substring(0, min(64, payload.length))}...');
        await LogService.instance.log('ADB PublicKey payload (base64...): ${payload.substring(0, 64)}...');
        await _storage.write(key: 'last_pub_payload', value: payload);
      }

      final actualFingerprint = _computeActualAdbFingerprint();
      if (actualFingerprint != null) {
        debugPrint("🔑 ACTUAL TV FINGERPRINT (MD5): $actualFingerprint");
        await LogService.instance.log("🔑 TV will show fingerprint: $actualFingerprint");
      }

      // ✅ Only create new connection if we don't have one or host/port changed
      debugPrint('🔄 Creating new AdbConnection for $effectiveHost:$effectivePort');
      // Don't disconnect old one - just replace reference
      _connection = AdbConnection(effectiveHost, effectivePort, keyManager.crypto!);

      _connSub?.cancel();
      try {
        _connSub = _connection!.onConnectionChanged.listen((state) {
          if (!state && connectionState != ConnectionState.disconnected) {
            _handleConnectionLoss();
          }
          onStateChanged();
        });
      } catch (_) {}

      final ok = await _connection!.connect();
      if (!ok) {
        debugPrint("❌ Connection failed");
        connectionState = ConnectionState.disconnected;
        await _cleanupConnection(fullDisconnect: true);
        return;
      }

      await shellQueue.openShell(_connection!);
      connectionState = ConnectionState.connected;

      await keyManager.markKeysAuthorized();

      await _storage.write(key: lastIpKey, value: effectiveHost);
      await _storage.write(key: lastPortKey, value: effectivePort.toString());

      ip = effectiveHost;
      port = effectivePort;
      debugPrint("✅ Connected: $effectiveHost:$effectivePort");
      await LogService.instance.log("✅ Connected: $effectiveHost:$effectivePort");
      onStateChanged();
    } catch (e, st) {
      debugPrint("Connect error: $e\n$st");
      await _cleanupConnection(fullDisconnect: true);
    } finally {
      _connectBusy = false;
      onStateChanged();
    }
  }

  // ✅ NEW: Add parameter to control whether to fully disconnect
  Future<void> disconnect({bool keepSession = false}) async {
    if (_disconnectBusy || connectionState == ConnectionState.disconnected) {
      debugPrint("⚠️ Disconnect already in progress or disconnected");
      return;
    }
    
    _disconnectBusy = true;
    
    try {
      debugPrint("Disconnecting from device (keepSession: $keepSession)");
      LogService.instance.log("Disconnecting from device");
      
      _stopKeepAlive();
      shellQueue.closeShell();
      
      await _connSub?.cancel();
      _connSub = null;
      
      connectionState = ConnectionState.disconnected;
      
      await Future.delayed(const Duration(milliseconds: 50));
      
      // ✅ Only actually disconnect if not keeping session
      if (!keepSession) {
        try {
          _connection?.disconnect();
        } catch (e) {
          debugPrint("Disconnect error (safe to ignore): $e");
        }
        _connection = null;
      } else {
        debugPrint("🔒 Keeping AdbConnection instance alive for session reuse");
      }
      
      debugPrint("Disconnected from device");
      LogService.instance.log("Disconnected from device");
      
      onStateChanged();
    } finally {
      _disconnectBusy = false;
    }
  }

  // Future<void> sleep() async {
  //   if (connectionState != ConnectionState.connected) return;
  //   connectionState = ConnectionState.sleeping;
  //   _startKeepAlive();
  //   onStateChanged();
  // }

  Future<void> wake() async {
    if (connectionState != ConnectionState.sleeping) return;
    if (_connection == null || !shellQueue.hasShell) {
      await connect();
      return;
    }
    _stopKeepAlive();
    connectionState = ConnectionState.connected;
    onStateChanged();
  }

  Future<void> _handleConnectionLoss() async {
    if (connectionState == ConnectionState.disconnected || _disconnectBusy) {
      return;
    }
    
    debugPrint("⚠️ Connection lost, attempting reconnect");
    final savedIp = ip;
    final savedPort = port;
    // ✅ Don't fully disconnect - keep session
    await _cleanupConnection(fullDisconnect: false);
    if (savedIp != null) await connect(host: savedIp, p: savedPort);
  }

  // ✅ Modified to optionally keep connection instance
  Future<void> _cleanupConnection({bool fullDisconnect = false}) async {
    await _connSub?.cancel();
    _connSub = null;
    
    await Future.delayed(const Duration(milliseconds: 50));
    
    shellQueue.closeShell();
    
    if (fullDisconnect) {
      try {
        _connection?.disconnect();
      } catch (e) {
        debugPrint("Cleanup disconnect error (safe to ignore): $e");
      }
      _connection = null;
    }
    
    connectionState = ConnectionState.disconnected;
    onStateChanged();
  }

  // void _startKeepAlive() {
  //   _keepAliveTimer?.cancel();
  //   _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
  //     if (connectionState == ConnectionState.sleeping && _connection != null) {
  //       try {
  //         await shellQueue.sendKeepAlive();
  //       } catch (_) {
  //         await _handleConnectionLoss();
  //       }
  //     }
  //   });
  // }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  AdbConnection? get connection => _connection;
}
