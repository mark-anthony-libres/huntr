import 'package:flutter/material.dart';
import '../../theme.dart';

/// The orange call-to-action button. Faded and inert while [onPressed] is
/// null.
class GradientButton extends StatelessWidget {
  const GradientButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
            gradient: HuntrColors.accentGradient,
            borderRadius: BorderRadius.all(Radius.circular(30))),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.black,
              minimumSize: const Size.fromHeight(52)),
          icon: Icon(icon),
          label: Text(label),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
