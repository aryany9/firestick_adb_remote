import 'package:flutter/material.dart' hide ConnectionState;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../../data/adb/adb_manager.dart';

class RemoteController extends ChangeNotifier {
  final AdbManager adb;

  RemoteController(this.adb);

  final ipController = TextEditingController();
  final portController = TextEditingController(text: "5555");

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
    await adb.connect(
      host: ipController.text,
      p: int.parse(portController.text),
    );
    saveLastDevice(ipController.text, int.parse(portController.text));
    notifyListeners();
  }

  Future<void> connectLast({required String ip, required int port}) async {
    await adb.connect(host: ip, p: port);
    saveLastDevice(ipController.text, int.parse(portController.text));
    notifyListeners();
  }

  Future<bool> checkWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }

  void showWifiError(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Please connect to Wi-Fi")));
  }

  void disconnect() {
    adb.disconnect();
    notifyListeners();
  }

  void sleep() {
    adb.sleep();
    notifyListeners();
  }

  // Remote actions
  Future<void> up() => adb.dpadUp();
  Future<void> down() => adb.dpadDown();
  Future<void> left() => adb.dpadLeft();
  Future<void> right() => adb.dpadRight();
  Future<void> ok() => adb.dpadCenter();
  Future<void> back() => adb.back();
  Future<void> home() => adb.home();
  Future<void> menu() => adb.menu();
  Future<void> volUp() => adb.volUp();
  Future<void> volDown() => adb.volDown();
  Future<void> mute() => adb.mute();

  // UI Display Helpers
  Color get statusColor => {
    ConnectionState.connected: Colors.green,
    ConnectionState.connecting: Colors.orange,
    ConnectionState.sleeping: Colors.blue,
    ConnectionState.disconnected: Colors.grey,
  }[adb.connectionState]!;

  IconData get statusIcon => {
    ConnectionState.connected: Icons.check_circle,
    ConnectionState.connecting: Icons.sync,
    ConnectionState.sleeping: Icons.bedtime,
    ConnectionState.disconnected: Icons.cancel,
  }[adb.connectionState]!;

  String get statusText => adb.connectionState.name;

  String get statusDetail =>
      adb.connected ? '${adb.ip}:${adb.port}' : 'Not connected';
}
