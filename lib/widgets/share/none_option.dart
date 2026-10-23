import 'package:flutter/material.dart';
import '../../theme.dart';

class NoneOption extends StatelessWidget {
  const NoneOption({super.key, required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: const Icon(Icons.block, color: HuntrColors.muted),
      title: const Text('Don\'t share an album'),
      trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? HuntrColors.orange : HuntrColors.muted),
      onTap: onTap,
    );
  }
}
