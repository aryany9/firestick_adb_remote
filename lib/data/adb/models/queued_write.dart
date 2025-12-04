import 'dart:async';
import 'dart:typed_data';

class QueuedWrite {
  final Uint8List bytes;
  final Completer<bool> completer;
  final DateTime enqueuedAt;

  QueuedWrite(this.bytes)
      : completer = Completer<bool>(),
        enqueuedAt = DateTime.now();
}
