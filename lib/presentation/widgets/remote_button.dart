import 'package:flutter/material.dart';

class RemoteButton extends StatefulWidget {
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
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final btnSize = widget.size ?? 72.0;
    final iconSize = (btnSize * 0.45).clamp(20.0, 48.0);

    // Neumorphic color setup
    final baseColor = cs.surface;
    final lightShadow = Colors.white.withOpacity(0.8);
    final darkShadow = Colors.black.withOpacity(0.15);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        width: btnSize,
        height: btnSize,
        decoration: BoxDecoration(
          shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circular ? null : BorderRadius.circular(12),
          color: widget.primary ? cs.primary : baseColor,
          boxShadow: _isPressed
              ? [
                  // Pressed state - subtle inner shadow effect
                  BoxShadow(
                    color: darkShadow,
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: lightShadow,
                    offset: const Offset(-2, -2),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ]
              : [
                  // Unpressed state - outer shadow for lifted effect
                  BoxShadow(
                    color: darkShadow,
                    offset: const Offset(4, 4),
                    blurRadius: 8,
                  ),
                  BoxShadow(
                    color: lightShadow,
                    offset: const Offset(-4, -4),
                    blurRadius: 8,
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: widget.circular ? null : BorderRadius.circular(12),
            splashColor: (widget.primary ? cs.onPrimary : cs.onSurface)
                .withOpacity(0.1),
            child: Center(
              child: widget.circular
                  ? Icon(
                      widget.icon,
                      size: iconSize,
                      color: widget.primary ? cs.onPrimary : cs.onSurface,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.icon,
                          size: iconSize,
                          color: widget.primary ? cs.onPrimary : cs.onSurface,
                        ),
                        if (widget.label != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.label!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontSize: 12,
                                  color: widget.primary
                                      ? cs.onPrimary
                                      : cs.onSurface,
                                ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
