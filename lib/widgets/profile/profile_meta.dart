import 'package:flutter/material.dart';
import '../../theme.dart';

class ProfileMeta extends StatelessWidget {
  const ProfileMeta(
      {super.key,
      this.icon,
      this.leading,
      required this.label,
      this.color = HuntrColors.muted});
  final IconData? icon;
  final Widget? leading;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      leading ?? Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 15.5)),
      ),
    ]);
  }
}
