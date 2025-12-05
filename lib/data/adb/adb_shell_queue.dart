import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firestick_adb_remote/data/adb/models/queued_write.dart';
import 'package:flutter/material.dart';
import 'package:flutter_adb/adb_connection.dart';
import 'package:flutter_adb/adb_stream.dart';

class AdbShellQueue {
  AdbStream? _shell;
  final Queue<QueuedWrite> _writeQueue = Queue<QueuedWrite>();
  bool _processingQueue = false;

  AdbStream? get shell => _shell;
  bool get hasShell => _shell != null;

  Future<void> openShell(AdbConnection connection) async {
    if (_shell != null) return;

    try {
      _shell = await connection.openShell();
      _shell!.onPayload.listen(
        (_) {},
        onError: (e) => _shell = null,
        onDone: () => _shell = null,
      );
    } catch (e) {
      debugPrint("Shell open error: $e");
      _shell = null;
    }
  }

  void closeShell() {
    _shell?.sendClose();
    _shell = null;
    _writeQueue.clear();
    _processingQueue = false;
  }

  Future<bool> sendCommand(String cmd) async {
    if (_shell == null) return false;

    final bytes = Uint8List.fromList(utf8.encode('$cmd\n'));
    if (_writeQueue.isEmpty) {
      final ok = await _tryImmediateWrite(bytes);
      if (ok) return true;
    }

    final item = QueuedWrite(bytes);
    _writeQueue.add(item);
    _processQueue();
    return item.completer.future;
  }

  Future<bool> _tryImmediateWrite(Uint8List bytes) async {
    if (_shell == null) return false;
    try {
      final ok = await _shell!.write(bytes, false);
      if (ok) return true;
      return await _shell!.write(bytes, false);
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
        if (_shell != null) {
          ok = await _shell!.write(item.bytes, false);
          if (!ok) ok = await _shell!.write(item.bytes, false);
        }
      } catch (_) {}
      if (!item.completer.isCompleted) item.completer.complete(ok);
      await Future.microtask(() {});
    }
    _processingQueue = false;
  }

  // Future<bool> sendKeepAlive() async {
  //   return _tryImmediateWrite(Uint8List.fromList(utf8.encode('\n')));
  // }
}
