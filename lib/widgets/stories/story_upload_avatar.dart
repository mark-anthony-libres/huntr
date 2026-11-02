import 'package:flutter/material.dart';

import '../../services/story_upload.dart';
import '../../theme.dart';

/// My avatar while a story posts in the background ([storyUpload]): a ring
/// filling as it's sent (turning while the server gets it ready), or a red
/// mark when it wasn't posted. Otherwise just [child].
class StoryUploadAvatar extends StatelessWidget {
  const StoryUploadAvatar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: storyUpload,
        builder: (context, _) {
          final progress = storyUpload.progress;
          final failed = storyUpload.error != null;
          if (progress == null && !failed) return child;
          return Stack(fit: StackFit.expand, children: [
            Padding(
              padding: const EdgeInsets.all(5),
              child: Opacity(opacity: 0.55, child: ClipOval(child: child)),
            ),
            if (progress != null)
              CircularProgressIndicator(
                key: const Key('storyUploadProgress'),
                // sent: how much; then the server's part: turning
                value: progress < 1 ? progress : null,
                strokeWidth: 3,
                color: HuntrColors.orange,
                backgroundColor: Colors.white24,
              )
            else
              const Align(
                alignment: Alignment.bottomRight,
                child: CircleAvatar(
                  key: Key('storyUploadFailed'),
                  radius: 11,
                  backgroundColor: HuntrColors.coral,
                  child: Icon(Icons.priority_high_rounded,
                      size: 15, color: Colors.white),
                ),
              ),
          ]);
        },
      );
}
