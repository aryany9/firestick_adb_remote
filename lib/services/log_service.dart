import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LogService {
  LogService._internal();
  static final LogService instance = LogService._internal();

  // Backing field for the developer mode flag. Use the getter/setter
  // so updates are persisted to secure storage.
  bool _developerModeEnabled = false;
  bool get developerModeEnabled => _developerModeEnabled;
  set developerModeEnabled(bool value) {
    _developerModeEnabled = value;
    // Persist the value (write without awaiting to avoid forcing callers to be async).
    try {
      _secureStorage ??= const FlutterSecureStorage();
      _secureStorage!.write(key: _devModeKey, value: value ? '1' : '0');
    } catch (_) {
      // Swallow storage errors - logging not available at this point.
    }
  }

  File? _logFile;
  FlutterSecureStorage? _secureStorage;
  static const String _devModeKey = 'developer_mode_enabled';

  // Initialize log file
  Future<void> init() async {
    // Initialize secure storage and load persisted developer-mode flag.
    _secureStorage ??= const FlutterSecureStorage();
    try {
      final stored = await _secureStorage!.read(key: _devModeKey);
      _developerModeEnabled = stored == '1';
    } catch (_) {
      // ignore secure storage read errors and keep default value
      _developerModeEnabled = _developerModeEnabled;
    }

    // Initialize log file
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File("${dir.path}/app_logs.txt");
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
  }

  // Main logging function
  Future<void> log(String message) async {
    if (!developerModeEnabled) return;

    if (_logFile == null) return;

    final timestamp = DateTime.now().toIso8601String();
    await _logFile!.writeAsString(
      "[$timestamp] $message\n",
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<String> readLogs() async {
    if (_logFile == null) return "";
    if (!await _logFile!.exists()) return "";
    return _logFile!.readAsString();
  }

  Future<void> clearLogs() async {
    if (_logFile == null) return;
    await _logFile!.writeAsString("");
  }

  Future<int> getLogSizeBytes() async {
    if (_logFile == null || !await _logFile!.exists()) return 0;
    return _logFile!.length();
  }
}
