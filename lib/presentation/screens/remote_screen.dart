import 'package:flutter/material.dart' hide ConnectionState;
import 'package:provider/provider.dart';
import '../state/remote_controller.dart';
import '../widgets/connection_section.dart';
import '../widgets/remote_controls.dart';

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Fire TV Remote')),
      body: LayoutBuilder(
        builder: (_, constraints) {
          final isWide = constraints.maxWidth > 650;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ConnectionSection(controller: controller),
                    const SizedBox(height: 24),

                    // Remote Controls
                    if (controller.isActive)
                      Expanded(
                        child: SingleChildScrollView(
                          child: RemoteControls(controller: controller),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
