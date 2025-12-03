import 'package:flutter/material.dart';

class RemoteButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool primary;
  final VoidCallback onTap;

  const RemoteButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.label,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? Colors.deepOrange : null,
        foregroundColor: primary ? Colors.white : null,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label!, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
