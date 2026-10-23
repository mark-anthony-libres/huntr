import 'package:flutter/material.dart';
import '../../theme.dart';

class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key, required this.bodySize, this.dense = false});

  final double bodySize;

  /// Tighter padding for small screens.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: dense || compact ? 14 : 24,
      ),
      decoration: BoxDecoration(
        color: HuntrColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C303A)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 36 : 64,
            child: Icon(
              Icons.verified_user_outlined,
              color: HuntrColors.orange,
              size: dense || compact ? 30 : 54,
            ),
          ),
          Container(
            width: 1,
            height: dense || compact ? 40 : 60,
            margin: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
            color: const Color(0xFF353944),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your social accounts stay yours',
                  style: TextStyle(
                    fontSize: bodySize < 20 ? 15 : 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'We never post anything to social media.',
                  style: TextStyle(
                    color: HuntrColors.muted,
                    fontSize: bodySize < 20 ? 14 : 18,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
