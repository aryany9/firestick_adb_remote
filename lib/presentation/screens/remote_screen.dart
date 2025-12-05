import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';
import 'package:firestick_adb_remote/theme/responsive.dart';
import '../state/remote_controller.dart';
import '../widgets/connection_section.dart';
import '../widgets/remote_controls.dart';

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Fire TV Remote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, "/settings");
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = context.responsivePadding;
            final maxWidth = context.isDesktop ? 600.0 : 450.0;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: padding,
                  child: Column(
                    children: [
                      ConnectionSection(controller: controller),
                      SizedBox(height: context.responsiveSpacing * 2),
                      // Remote Controls: show only when active/connected
                      if (controller.isActive)
                        Expanded(
                          child: SingleChildScrollView(
                            child: RemoteControls(controller: controller),
                          ),
                        )
                      else
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Not connected. Connect to a device to use remote controls.',
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(
                                  height: context.responsiveSpacing * 1.5,
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pushNamed(context, "/settings"),
                                  child: const Text('Open Settings'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: controller.isActive
          ? SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.responsivePadding.left,
                  vertical: context.responsiveSpacing,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: controller.disconnect,
                    icon: const Icon(Icons.power_off),
                    label: const Text('Disconnect'),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
