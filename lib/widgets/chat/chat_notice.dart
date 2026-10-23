import 'package:flutter/material.dart';
import '../../theme.dart';

class ChatNotice extends StatelessWidget {
  const ChatNotice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.handshake_outlined,
            size: 15, color: HuntrColors.orange),
        const SizedBox(width: 6),
        Flexible(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 12.5, color: HuntrColors.muted))),
      ]),
    );
  }
}
