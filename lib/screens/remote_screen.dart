// Example RemoteScreen showing how to use sleep/wake functionality
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';
import '../adb_manager.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({Key? key}) : super(key: key);

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> with WidgetsBindingObserver {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '5555');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize with saved IP if available
    final manager = context.read<AdbManager>();
    if (manager.ip != null) {
      _ipController.text = manager.ip!;
      _portController.text = manager.port.toString();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final manager = context.read<AdbManager>();
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background - put connection to sleep
        if (manager.connected) {
          debugPrint('App going to background - sleeping connection');
          manager.sleep();
        }
        break;
      case AppLifecycleState.resumed:
        // App returning to foreground - wake connection
        if (manager.sleeping) {
          debugPrint('App returning to foreground - waking connection');
          manager.wake();
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire TV Remote'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Consumer<AdbManager>(
        builder: (context, manager, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection Status Card
                _buildStatusCard(manager),
                const SizedBox(height: 16),
                
                // Connection Controls (only show when not connected)
                if (!manager.isActive) ...[
                  _buildConnectionForm(manager),
                  const SizedBox(height: 16),
                ],
                
                // Connection Action Buttons
                _buildConnectionButtons(manager),
                const SizedBox(height: 24),
                
                // Remote Control (only when connected or sleeping)
                if (manager.isActive) ...[
                  _buildRemoteControls(manager),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(AdbManager manager) {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusDetail;

    switch (manager.connectionState) {
      case ConnectionState.connected:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Connected';
        statusDetail = '${manager.ip}:${manager.port}';
        break;
      case ConnectionState.connecting:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusText = 'Connecting...';
        statusDetail = '${manager.ip}:${manager.port}';
        break;
      case ConnectionState.sleeping:
        statusColor = Colors.blue;
        statusIcon = Icons.bedtime;
        statusText = 'Sleeping';
        statusDetail = 'Connection kept alive';
        break;
      case ConnectionState.disconnected:
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
        statusText = 'Disconnected';
        statusDetail = 'Not connected';
        break;
    }

    return Card(
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusDetail,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionForm(AdbManager manager) {
    return Column(
      children: [
        TextField(
          controller: _ipController,
          decoration: const InputDecoration(
            labelText: 'Fire TV IP Address',
            hintText: '192.168.1.100',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.tv),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _portController,
          decoration: const InputDecoration(
            labelText: 'Port',
            hintText: '5555',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.settings_ethernet),
          ),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  Widget _buildConnectionButtons(AdbManager manager) {
    return Row(
      children: [
        // Connect Button
        if (!manager.isActive)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: manager.connecting
                  ? null
                  : () {
                      final ip = _ipController.text.trim();
                      final port = int.tryParse(_portController.text) ?? 5555;
                      if (ip.isNotEmpty) {
                        manager.connect(host: ip, p: port);
                      }
                    },
              icon: const Icon(Icons.power),
              label: const Text('Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        
        // Sleep Button (when connected)
        if (manager.connected) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => manager.sleep(),
              icon: const Icon(Icons.bedtime),
              label: const Text('Sleep'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        
        // Wake Button (when sleeping)
        if (manager.sleeping) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => manager.wake(),
              icon: const Icon(Icons.wb_sunny),
              label: const Text('Wake'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        
        // Disconnect Button (when connected or sleeping)
        if (manager.isActive)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => manager.disconnect(),
              icon: const Icon(Icons.power_off),
              label: const Text('Disconnect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRemoteControls(AdbManager manager) {
    return Column(
      children: [
        const Text(
          'Remote Control',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
        // D-pad
        Column(
          children: [
            _buildRemoteButton(
              icon: Icons.keyboard_arrow_up,
              onPressed: manager.dpadUp,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildRemoteButton(
                  icon: Icons.keyboard_arrow_left,
                  onPressed: manager.dpadLeft,
                ),
                const SizedBox(width: 8),
                _buildRemoteButton(
                  icon: Icons.circle,
                  label: 'OK',
                  onPressed: manager.dpadCenter,
                  primary: true,
                ),
                const SizedBox(width: 8),
                _buildRemoteButton(
                  icon: Icons.keyboard_arrow_right,
                  onPressed: manager.dpadRight,
                ),
              ],
            ),
            _buildRemoteButton(
              icon: Icons.keyboard_arrow_down,
              onPressed: manager.dpadDown,
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // Navigation buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildRemoteButton(
              icon: Icons.arrow_back,
              label: 'Back',
              onPressed: manager.back,
            ),
            _buildRemoteButton(
              icon: Icons.home,
              label: 'Home',
              onPressed: manager.home,
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Volume controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildRemoteButton(
              icon: Icons.volume_down,
              label: 'Vol -',
              onPressed: manager.volDown,
            ),
            _buildRemoteButton(
              icon: Icons.volume_mute,
              label: 'Mute',
              onPressed: manager.mute,
            ),
            _buildRemoteButton(
              icon: Icons.volume_up,
              label: 'Vol +',
              onPressed: manager.volUp,
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // Info card
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tip: Use "Sleep" instead of "Disconnect" to avoid re-authorization prompts',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteButton({
    required IconData icon,
    String? label,
    required Future<bool> Function() onPressed,
    bool primary = false,
  }) {
    return ElevatedButton(
      onPressed: () async {
        final success = await onPressed();
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Command failed')),
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ? Colors.deepOrange : Colors.grey[300],
        foregroundColor: primary ? Colors.white : Colors.black87,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}