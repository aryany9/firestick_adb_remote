import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LogService {
  LogService._internal();
  static final LogService instance = LogService._internal();

  bool developerModeEnabled = false; // Toggle from settings

  File? _logFile;

  // Initialize log file
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File("${dir.path}/app_logs.txt");
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
  }

  // Main logging function
  Future<void> log(String message) async {
    if (!developerModeEnabled) return;

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
