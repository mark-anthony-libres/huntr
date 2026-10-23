import 'package:flutter/material.dart';
import '../../theme.dart';

class EmptyChats extends StatelessWidget {
  const EmptyChats({super.key, required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.forum_outlined, size: 56, color: HuntrColors.muted),
          const SizedBox(height: 12),
          Text('No chats yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Say hi to someone nearby to start a conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HuntrColors.muted)),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: onExplore, child: const Text('Explore people')),
        ],
      ),
    );
  }
}
