import 'package:flutter/material.dart';

class RemoteButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool primary;
  final VoidCallback onTap;
  final double? size;
  final bool circular;

  const RemoteButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.label,
    this.primary = false,
    this.size,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btnSize = size ?? 72.0;
    final iconSize = (btnSize * 0.45).clamp(20.0, 48.0);
    final bg = primary ? cs.primary : cs.surfaceVariant;
    final fg = primary ? cs.onPrimary : cs.onSurfaceVariant;

    return FilledButton.tonal(
      onPressed: onTap,
      style:
          FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            padding: EdgeInsets.zero,
            minimumSize: Size(btnSize, btnSize),
            fixedSize: Size(btnSize, btnSize),
            shape: circular
                ? const CircleBorder()
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
            elevation: 2,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.pressed))
                return fg.withOpacity(0.12);
              return null;
            }),
          ),
      child: circular
          ? Icon(icon, size: iconSize)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconSize),
                if (label != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    label!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                  ),
                ],
              ],
            ),
    );
  }
}
