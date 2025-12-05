import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:firestick_adb_remote/theme/responsive.dart';
import 'package:flutter/material.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String logs = "";
  int sizeBytes = 0;

  @override
  void initState() {
    super.initState();
    loadLogs();
  }

  Future<void> loadLogs() async {
    final txt = await LogService.instance.readLogs();
    final s = await LogService.instance.getLogSizeBytes();
    setState(() {
      logs = txt;
      sizeBytes = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final padding = context.responsivePadding;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Application Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await LogService.instance.clearLogs();
              await loadLogs();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: padding,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outline.withOpacity(0.2)),
              ),
            ),
            child: Text(
              "Log file size: ${(sizeBytes / 1024).toStringAsFixed(2)} KB",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: padding,
              child: Text(
                logs.isEmpty ? "No logs yet" : logs,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
