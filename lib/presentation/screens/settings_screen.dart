import 'package:firestick_adb_remote/services/log_service.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool devMode = LogService.instance.developerModeEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text("Enable Developer Mode"),
            subtitle: const Text("Enable internal logging & diagnostics"),
            value: devMode,
            onChanged: (value) {
              setState(() {
                devMode = value;
                LogService.instance.developerModeEnabled = value;
              });
            },
          ),

          if (devMode)
            ListTile(
              title: const Text("View Logs"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pushNamed(context, "/logs");
              },
            ),
        ],
      ),
    );
  }
}
