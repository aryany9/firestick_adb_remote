import 'package:flutter/material.dart';
import '../state/remote_controller.dart';
import 'remote_button.dart';

class RemoteControls extends StatelessWidget {
  final RemoteController controller;
  const RemoteControls({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // D-Pad
        Column(
          children: [
            RemoteButton(icon: Icons.keyboard_arrow_up, onTap: controller.up),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RemoteButton(
                  icon: Icons.keyboard_arrow_left,
                  onTap: controller.left,
                ),
                const SizedBox(width: 8),
                RemoteButton(
                  icon: Icons.circle,
                  label: 'OK',
                  primary: true,
                  onTap: controller.ok,
                ),
                const SizedBox(width: 8),
                RemoteButton(
                  icon: Icons.keyboard_arrow_right,
                  onTap: controller.right,
                ),
              ],
            ),

            const SizedBox(height: 8),
            RemoteButton(
              icon: Icons.keyboard_arrow_down,
              onTap: controller.down,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Nav
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RemoteButton(
              icon: Icons.arrow_back,
              label: 'Back',
              onTap: controller.back,
            ),
            RemoteButton(
              icon: Icons.home,
              label: 'Home',
              onTap: controller.home,
            ),
            RemoteButton(
              icon: Icons.menu,
              label: 'Menu',
              onTap: controller.menu,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Volume
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RemoteButton(
              icon: Icons.volume_down,
              label: 'Vol -',
              onTap: controller.volDown,
            ),
            RemoteButton(
              icon: Icons.volume_mute,
              label: 'Mute',
              onTap: controller.mute,
            ),
            RemoteButton(
              icon: Icons.volume_up,
              label: 'Vol +',
              onTap: controller.volUp,
            ),
          ],
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
