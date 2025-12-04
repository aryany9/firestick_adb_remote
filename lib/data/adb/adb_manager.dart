import 'dart:async';

import 'package:firestick_adb_remote/data/adb/adb_connection_handler.dart';
import 'package:firestick_adb_remote/data/adb/adb_key_manager.dart';
import 'package:firestick_adb_remote/data/adb/adb_shell_queue.dart';
import 'package:firestick_adb_remote/data/adb/constants.dart';
import 'package:firestick_adb_remote/data/adb/models/connection_state.dart';
import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final _storage = FlutterSecureStorage();

class AdbManager extends ChangeNotifier {
  late final AdbKeyManager _keyManager;
  late final AdbShellQueue _shellQueue;
  late final AdbConnectionHandler _connectionHandler;

  Timer? _repeatTimer;
  String? _repeatCommand;

  AdbManager() {
    _keyManager = AdbKeyManager(_storage);
    _shellQueue = AdbShellQueue();
    _connectionHandler = AdbConnectionHandler(
      storage: _storage,
      keyManager: _keyManager,
      shellQueue: _shellQueue,
      onStateChanged: notifyListeners,
    );
    _init();
  }

  // ========= Public getters =========
  String? get ip => _connectionHandler.ip;
  int get port => _connectionHandler.port;
  ConnectionState get connectionState => _connectionHandler.connectionState;
  bool get connected => _connectionHandler.connected;
  bool get connecting => _connectionHandler.connecting;
  bool get sleeping => _connectionHandler.sleeping;
  bool get isActive => _connectionHandler.isActive;
  String? get keyFingerprint => _keyManager.keyFingerprint;
  bool get keysAuthorized => _keyManager.keysAuthorized;

  Future<void> _init() async {
debugPrint("🔑 Initializing AdbManager");
    await LogService.instance.log("🔑 Initializing AdbManager");

    await _keyManager.initialize();
    await _connectionHandler.initialize();

    debugPrint(
      "✅ AdbManager init: IP=$ip:$port, KeysAuth=$keysAuthorized, Fingerprint=$keyFingerprint",
    );
    await LogService.instance.log(
      "✅ AdbManager init: IP=$ip:$port, KeysAuth=$keysAuthorized, Fingerprint=$keyFingerprint",
    );

    notifyListeners();
  }

  // ========= Connection methods =========
  Future<void> connect({String? host, int? p}) =>
      _connectionHandler.connect(host: host, p: p);

  Future<void> disconnect() => _connectionHandler.disconnect();

  Future<void> sleep() => _connectionHandler.sleep();

  Future<void> wake() => _connectionHandler.wake();

  Future<void> regenerateKeys() async {
    await _keyManager.regenerateKeys();
    notifyListeners();
  }

  // ========= Shell commands =========
  Future<bool> sendShellCommand(String cmd) async {
    if (_connectionHandler.connection == null) return false;
    if (connectionState == ConnectionState.sleeping) await wake();
    if (!_shellQueue.hasShell && _connectionHandler.connection != null) {
      await _shellQueue.openShell(_connectionHandler.connection!);
    }
    return _shellQueue.sendCommand(cmd);
  }

  // ========= Keycode helpers =========
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
  Future<bool> menu() => sendShellCommand('input keyevent KEYCODE_MENU');

  // ========= Repeat functionality =========
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

  @override
  void dispose() {
    stopRepeat();
    disconnect();
    super.dispose();
  }
}
