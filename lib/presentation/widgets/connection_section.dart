import 'package:flutter/material.dart';
import '../state/remote_controller.dart';

class ConnectionSection extends StatelessWidget {
  final RemoteController controller;
  const ConnectionSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // if (!controller.isActive)
        _buildLastConnectedCard(context),
        const SizedBox(height: 12),

        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _statusTile(),
                const SizedBox(height: 16),
                if (!controller.isActive) _buildConnectForm(context),
                if (controller.isActive) _buildActiveButtons(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // LAST CONNECTED DEVICE CARD
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildLastConnectedCard(BuildContext context) {
    if (controller.lastIp == null || controller.lastIp!.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () async {
        final wifiOk = await controller.checkWifi();
        if (!wifiOk) {
          controller.showWifiError(context);
          return;
        }
        controller.connectLast(
          ip: controller.lastIp!,
          port: controller.lastPort,
        );
      },
      child: Card(
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.history, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Last connected: ${controller.lastIp}:${controller.lastPort}',
                  style: TextStyle(fontSize: 14, color: Colors.orange.shade800),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black45),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STATUS TILE
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _statusTile() {
    final color = controller.statusColor;

    return Row(
      children: [
        Icon(controller.statusIcon, color: color, size: 32),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.statusText,
              style: TextStyle(
                fontSize: 18,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              controller.statusDetail,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CONNECT FORM WITH WIFI CHECK
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildConnectForm(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller.ipController,
          decoration: const InputDecoration(
            label: Text('Fire TV IP Address'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.portController,
          decoration: const InputDecoration(
            label: Text('Port'),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              final wifiOk = await controller.checkWifi();
              if (!wifiOk) {
                controller.showWifiError(context);
                return;
              }
              controller.connect();
            },
            icon: const Icon(Icons.power),
            label: const Text('Connect'),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ACTIVE BUTTONS
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildActiveButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: controller.sleep,
            icon: const Icon(Icons.bedtime),
            label: const Text('Sleep'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: controller.disconnect,
            icon: const Icon(Icons.power_off),
            label: const Text('Disconnect'),
          ),
        ),
      ],
    );
  }
}
