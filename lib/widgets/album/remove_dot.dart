import 'package:flutter/material.dart';

class RemoveDot extends StatelessWidget {
  const RemoveDot({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration:
            const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: const Icon(Icons.close, size: 15, semanticLabel: 'Remove photo'),
      ),
    );
  }
}
