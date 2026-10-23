import 'package:flutter/material.dart';
import '../../theme.dart';

class TimeDivider extends StatelessWidget {
  const TimeDivider({super.key, required this.time, required this.now});
  final DateTime time;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final clock =
        '$h:${time.minute.toString().padLeft(2, '0')} ${time.hour < 12 ? 'AM' : 'PM'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(sameDay ? 'Today $clock' : '${time.day}/${time.month} $clock',
          style: const TextStyle(fontSize: 12, color: HuntrColors.muted)),
    );
  }
}
