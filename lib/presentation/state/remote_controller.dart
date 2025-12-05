
import 'package:firestick_adb_remote/data/adb/adb_manager.dart';
import 'package:firestick_adb_remote/data/adb/models/connection_state.dart';
import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RemoteController extends ChangeNotifier {
  final AdbManager adb;

  RemoteController(this.adb) {
    _restoreLastDevice();
  }

  final ipController = TextEditingController();
  final portController = TextEditingController(text: "5555");

  Future<void> _restoreLastDevice() async {
    final lastIpStr = await _storage.read(key: _lastIpKey);
    final lastPortStr = await _storage.read(key: _lastPortKey);
    if (lastIpStr != null) {
      lastIp = lastIpStr;
      lastPort = int.tryParse(lastPortStr ?? '') ?? 5555;
      notifyListeners();
    }
  }

  // Use same storage keys as AdbManager
  static const _storage = FlutterSecureStorage();
  static const _lastIpKey = 'last_adb_ip';
  static const _lastPortKey = 'last_adb_port';

  bool get isActive => adb.isActive;
  String? lastIp;
  int lastPort = 5555;

  void saveLastDevice(String ip, int port) {
    lastIp = ip;
    lastPort = port;
    notifyListeners();
  }

  // Connection helpers
  Future<void> connect() async {
    try {
      debugPrint(
        "Attempting to connect to ${ipController.text}:${portController.text}",
      );
      await LogService.instance.log(
        "Attempting to connect to ${ipController.text}:${portController.text}",
      );
      await adb.connect(
        host: ipController.text,
        p: int.parse(portController.text),
      );
      saveLastDevice(ipController.text, int.parse(portController.text));
      debugPrint("Connected to ${ipController.text}:${portController.text}");
      await LogService.instance.log(
        "Connected to ${ipController.text}:${portController.text}",
      );
    } catch (e) {
      debugPrint("Connection error: $e");
      await LogService.instance.log("Connection error: $e");
    }
    notifyListeners();
  }

  Future<void> connectLast({required String ip, required int port}) async {
    try {
      debugPrint("Attempting to reconnect to $ip:$port");
      await LogService.instance.log("Attempting to reconnect to $ip:$port");
      await adb.connect(host: ip, p: port);
      saveLastDevice(ipController.text, int.parse(portController.text));
      debugPrint("Reconnected to $ip:$port");
      await LogService.instance.log("Reconnected to $ip:$port");
    } catch (e) {
      debugPrint("Reconnection error: $e");
      await LogService.instance.log("Reconnection error: $e");
    }
    notifyListeners();
  }

  Future<bool> checkWifi() async {
    try {
      debugPrint("Checking Wi-Fi connectivity");
      await LogService.instance.log("Checking Wi-Fi connectivity");
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      debugPrint("Wi-Fi connectivity status: $isWifi");
      await LogService.instance.log("Wi-Fi connectivity status: $isWifi");
      return isWifi;
    } catch (e) {
      debugPrint("Wi-Fi check error: $e");
      await LogService.instance.log("Wi-Fi check error: $e");
      return false;
    }
  }

  void showWifiError(BuildContext context) {
    try {
      debugPrint("Displaying Wi-Fi error message");
      LogService.instance.log("Displaying Wi-Fi error message");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please connect to Wi-Fi")));
    } catch (e) {
      debugPrint("Wi-Fi error display issue: $e");
      LogService.instance.log("Wi-Fi error display issue: $e");
    }
  }

  void disconnect() {
    try {
      debugPrint("Disconnecting from device");
      LogService.instance.log("Disconnecting from device");
      adb.disconnect();
      debugPrint("Disconnected from device");
      LogService.instance.log("Disconnected from device");
    } catch (e) {
      debugPrint("Disconnection error: $e");
      LogService.instance.log("Disconnection error: $e");
    }
    _restoreLastDevice();
    notifyListeners();
  }

  // void sleep() {
  //   try {
  //     debugPrint("Putting device to sleep");
  //     LogService.instance.log("Putting device to sleep");
  //     adb.sleep();
  //     debugPrint("Device is now in sleep mode");
  //     LogService.instance.log("Device is now in sleep mode");
  //   } catch (e) {
  //     debugPrint("Sleep error: $e");
  //     LogService.instance.log("Sleep error: $e");
  //   }
  //   notifyListeners();
  // }

  // Remote actions
  Future<void> up() async {
    try {
      debugPrint("Sending UP command");
      await LogService.instance.log("Sending UP command");
      await adb.dpadUp();
      debugPrint("UP command sent successfully");
      await LogService.instance.log("UP command sent successfully");
    } catch (e) {
      debugPrint("Up action error: $e");
      await LogService.instance.log("Up action error: $e");
    }
  }

  Future<void> down() async {
    try {
      debugPrint("Sending DOWN command");
      await LogService.instance.log("Sending DOWN command");
      await adb.dpadDown();
      debugPrint("DOWN command sent successfully");
      await LogService.instance.log("DOWN command sent successfully");
    } catch (e) {
      debugPrint("Down action error: $e");
      await LogService.instance.log("Down action error: $e");
    }
  }

  Future<void> left() async {
    try {
      debugPrint("Sending LEFT command");
      await LogService.instance.log("Sending LEFT command");
      await adb.dpadLeft();
      debugPrint("LEFT command sent successfully");
      await LogService.instance.log("LEFT command sent successfully");
    } catch (e) {
      debugPrint("Left action error: $e");
      await LogService.instance.log("Left action error: $e");
    }
  }

  Future<void> right() async {
    try {
      debugPrint("Sending RIGHT command");
      await LogService.instance.log("Sending RIGHT command");
      await adb.dpadRight();
      debugPrint("RIGHT command sent successfully");
      await LogService.instance.log("RIGHT command sent successfully");
    } catch (e) {
      debugPrint("Right action error: $e");
      await LogService.instance.log("Right action error: $e");
    }
  }

  Future<void> ok() async {
    try {
      debugPrint("Sending OK command");
      await LogService.instance.log("Sending OK command");
      await adb.dpadCenter();
      debugPrint("OK command sent successfully");
      await LogService.instance.log("OK command sent successfully");
    } catch (e) {
      debugPrint("OK action error: $e");
      await LogService.instance.log("OK action error: $e");
    }
  }

  Future<void> back() async {
    try {
      debugPrint("Sending BACK command");
      await LogService.instance.log("Sending BACK command");
      await adb.back();
      debugPrint("BACK command sent successfully");
      await LogService.instance.log("BACK command sent successfully");
    } catch (e) {
      debugPrint("Back action error: $e");
      await LogService.instance.log("Back action error: $e");
    }
  }

  Future<void> home() async {
    try {
      debugPrint("Sending HOME command");
      await LogService.instance.log("Sending HOME command");
      await adb.home();
      debugPrint("HOME command sent successfully");
      await LogService.instance.log("HOME command sent successfully");
    } catch (e) {
      debugPrint("Home action error: $e");
      await LogService.instance.log("Home action error: $e");
    }
  }

  Future<void> menu() async {
    try {
      debugPrint("Sending MENU command");
      await LogService.instance.log("Sending MENU command");
      await adb.menu();
      debugPrint("MENU command sent successfully");
      await LogService.instance.log("MENU command sent successfully");
    } catch (e) {
      debugPrint("Menu action error: $e");
      await LogService.instance.log("Menu action error: $e");
    }
  }

  Future<void> volUp() async {
    try {
      debugPrint("Sending VOLUME UP command");
      await LogService.instance.log("Sending VOLUME UP command");
      await adb.volUp();
      debugPrint("VOLUME UP command sent successfully");
      await LogService.instance.log("VOLUME UP command sent successfully");
    } catch (e) {
      debugPrint("Volume up error: $e");
      await LogService.instance.log("Volume up error: $e");
    }
  }

  Future<void> volDown() async {
    try {
      debugPrint("Sending VOLUME DOWN command");
      await LogService.instance.log("Sending VOLUME DOWN command");
      await adb.volDown();
      debugPrint("VOLUME DOWN command sent successfully");
      await LogService.instance.log("VOLUME DOWN command sent successfully");
    } catch (e) {
      debugPrint("Volume down error: $e");
      await LogService.instance.log("Volume down error: $e");
    }
  }

  Future<void> mute() async {
    try {
      debugPrint("Sending MUTE command");
      await LogService.instance.log("Sending MUTE command");
      await adb.mute();
      debugPrint("MUTE command sent successfully");
      await LogService.instance.log("MUTE command sent successfully");
    } catch (e) {
      debugPrint("Mute error: $e");
      await LogService.instance.log("Mute error: $e");
    }
  }

  // UI Display Helpers
  Color get statusColor => {
    ConnectionState.connected: Colors.green,
    ConnectionState.connecting: Colors.orange,
    // ConnectionState.sleeping: Colors.blue,
    ConnectionState.disconnected: Colors.grey,
  }[adb.connectionState]!;

  IconData get statusIcon => {
    ConnectionState.connected: Icons.check_circle,
    ConnectionState.connecting: Icons.sync,
    // ConnectionState.sleeping: Icons.bedtime,
    ConnectionState.disconnected: Icons.cancel,
  }[adb.connectionState]!;

  String get statusText => adb.connectionState.name;

  String get statusDetail =>
      adb.connected ? '${adb.ip}:${adb.port}' : 'Not connected';
}
