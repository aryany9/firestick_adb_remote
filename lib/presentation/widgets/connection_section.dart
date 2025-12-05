import 'package:flutter/material.dart';
import 'package:firestick_adb_remote/theme/responsive.dart';
import '../state/remote_controller.dart';

class ConnectionSection extends StatelessWidget {
  final RemoteController controller;
  const ConnectionSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final spacing = context.responsiveSpacing;

    return Column(
      children: [
        if (!controller.isActive) _buildLastConnectedCard(context),
        SizedBox(height: spacing),

        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(spacing),
            child: Column(
              children: [
                _statusTile(context),
                SizedBox(height: spacing * 1.5),
                if (!controller.isActive) _buildConnectForm(context),
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

    final cs = Theme.of(context).colorScheme;
    final spacing = context.responsiveSpacing;

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
        color: cs.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: EdgeInsets.all(spacing),
          child: Row(
            children: [
              Icon(Icons.history, color: cs.primary),
              SizedBox(width: spacing),
              Expanded(
                child: Text(
                  'Last connected: ${controller.lastIp}:${controller.lastPort}',
                  style: TextStyle(fontSize: 14, color: cs.onPrimaryContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STATUS TILE
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _statusTile(BuildContext context) {
    final color = controller.statusColor;
    final spacing = context.responsiveSpacing;

    return Row(
      children: [
        Icon(controller.statusIcon, color: color, size: 32),
        SizedBox(width: spacing),
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
              style: Theme.of(context).textTheme.bodySmall,
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
    final spacing = context.responsiveSpacing;

    return Column(
      children: [
        TextField(
          controller: controller.ipController,
          decoration: const InputDecoration(
            label: Text('Fire TV IP Address'),
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: spacing),
        TextField(
          controller: controller.portController,
          decoration: const InputDecoration(
            label: Text('Port'),
            border: OutlineInputBorder(),
          ),
        ),
        SizedBox(height: spacing * 1.5),
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
}
