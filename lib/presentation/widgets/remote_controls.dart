import 'package:flutter/material.dart';
import 'package:firestick_adb_remote/theme/responsive.dart';
import '../state/remote_controller.dart';
import 'remote_button.dart';

class RemoteControls extends StatelessWidget {
  final RemoteController controller;
  const RemoteControls({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.responsiveSpacing;

    // Sizes for buttons (mobile-friendly, responsive)
    final arrowSize = context.isMobile ? 80.0 : 96.0;
    final okSize = context.isMobile ? 108.0 : 128.0;
    final navSize = context.isMobile ? 88.0 : 104.0;
    final volSize = context.isMobile ? 88.0 : 104.0;

    return Card(
      color: cs.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing * 1.5,
          vertical: spacing * 1.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // D-Pad
            Column(
              children: [
                RemoteButton(
                  icon: Icons.keyboard_arrow_up,
                  onTap: controller.up,
                  size: arrowSize,
                ),
                SizedBox(height: spacing * 1.2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RemoteButton(
                      icon: Icons.keyboard_arrow_left,
                      onTap: controller.left,
                      size: arrowSize,
                    ),
                    SizedBox(width: spacing * 1.3),
                    RemoteButton(
                      icon: Icons.circle,
                      label: 'OK',
                      primary: true,
                      onTap: controller.ok,
                      size: okSize,
                      circular: true,
                    ),
                    SizedBox(width: spacing * 1.3),
                    RemoteButton(
                      icon: Icons.keyboard_arrow_right,
                      onTap: controller.right,
                      size: arrowSize,
                    ),
                  ],
                ),
                SizedBox(height: spacing * 1.2),
                RemoteButton(
                  icon: Icons.keyboard_arrow_down,
                  onTap: controller.down,
                  size: arrowSize,
                ),
              ],
            ),
            SizedBox(height: spacing * 2),
            // Nav
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RemoteButton(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onTap: controller.back,
                  size: navSize,
                ),
                RemoteButton(
                  icon: Icons.home,
                  label: 'Home',
                  onTap: controller.home,
                  size: navSize,
                ),
                RemoteButton(
                  icon: Icons.menu,
                  label: 'Menu',
                  onTap: controller.menu,
                  size: navSize,
                ),
              ],
            ),
            SizedBox(height: spacing * 2),
            // Volume
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RemoteButton(
                  icon: Icons.volume_down,
                  label: 'Vol -',
                  onTap: controller.volDown,
                  size: volSize,
                ),
                RemoteButton(
                  icon: Icons.volume_mute,
                  label: 'Mute',
                  onTap: controller.mute,
                  size: volSize,
                ),
                RemoteButton(
                  icon: Icons.volume_up,
                  label: 'Vol +',
                  onTap: controller.volUp,
                  size: volSize,
                ),
              ],
            ),
            SizedBox(height: spacing),
          ],
        ),
      ),
    );
  }
}
