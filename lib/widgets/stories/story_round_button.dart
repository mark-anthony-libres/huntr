import 'package:flutter/material.dart';

/// A round button over a story (or the camera): a dark see-through disc with a light
/// outline, so it stays visible whatever the video shows.
class StoryRoundButton extends StatelessWidget {
  const StoryRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
          fixedSize: Size(size, size),
        ),
        icon: Icon(icon, size: size * 0.6),
      );
}
