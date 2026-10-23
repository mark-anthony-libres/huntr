import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../theme.dart';

/// A photo or video in the chat. Until it's opened only a small blurred
/// preview shows ("Tap to view"); opening it is what starts the recipient's
/// countdown. My own while sending show the picked file with its progress.
class MediaBubble extends StatelessWidget {
  /// The tallest a photo or video bubble gets in the chat.
  static const _maxHeight = 300.0;

  const MediaBubble({
    super.key,
    required this.message,
    required this.now,
    required this.onOpen,
    this.onPreviewFailed,
  });

  final ChatMessage message;
  final DateTime now;
  final VoidCallback onOpen;

  /// The preview's link didn't load (e.g. it expired): fetch a new one.
  final VoidCallback? onPreviewFailed;

  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    final attachment = message.attachment;
    final upload = message.upload;
    final isVideo = attachment?.isVideo ?? upload?.isVideo ?? false;
    final expired = attachment?.expiredAt(now) ?? false;
    // tall photos show at most 3:4 and never taller than [_maxHeight] (the
    // preview is cropped to fit; opening it shows the whole picture)
    final ratio = attachment == null
        ? 1.0
        : (attachment.width / math.max(attachment.height, 1)).clamp(0.75, 1.5);
    final width = math.min(MediaQuery.sizeOf(context).width * 0.6, 260.0);
    final height = math.min(width / ratio, _maxHeight);

    final Widget content;
    if (expired) {
      content = _Expired(isVideo: isVideo);
    } else if (attachment == null && upload != null) {
      content = _Uploading(message: message, upload: upload);
    } else {
      content = _Preview(
        attachment: attachment!,
        now: now,
        fromMe: me,
        onFailed: onPreviewFailed,
      );
    }
    return Align(
      // only as wide as the bubble when there's room (e.g. beside the
      // reaction button); a full-width row still puts it on its side
      widthFactor: 1,
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Semantics(
          button: !expired && attachment != null,
          label: expired
              ? (isVideo ? 'Expired video' : 'Expired photo')
              : (isVideo ? 'Video, tap to view' : 'Photo, tap to view'),
          child: GestureDetector(
            key: Key('media-${message.id ?? message.clientId}'),
            onTap: expired || attachment == null ? null : onOpen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: width,
                // the expired note sizes itself (bigger text, more room)
                height: expired ? null : height,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The blurred preview with what tapping does.
class _Preview extends StatelessWidget {
  const _Preview(
      {required this.attachment,
      required this.now,
      required this.fromMe,
      this.onFailed});

  final ChatAttachment attachment;
  final DateTime now;
  final bool fromMe;
  final VoidCallback? onFailed;

  @override
  Widget build(BuildContext context) {
    final url = attachment.previewUrl;
    final expiresAt = attachment.expiresAt;
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
          decoration: BoxDecoration(gradient: HuntrColors.glowGradient)),
      if (url != null)
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // a plain <img> on web: no CORS needed for the bucket
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (context, error, stack) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => onFailed?.call());
              return const SizedBox.shrink();
            },
          ),
        ),
      const DecoratedBox(decoration: BoxDecoration(color: Color(0x33000000))),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                attachment.isVideo
                    ? Icons.play_arrow_rounded
                    : Icons.visibility_outlined,
                color: Colors.white,
                size: 20),
            const SizedBox(width: 6),
            Text(attachment.isVideo ? 'Play video' : 'Tap to view',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      if (attachment.isVideo && attachment.durationMs != null)
        Positioned(
          right: 10,
          top: 10,
          child: _Chip(
              icon: Icons.videocam_rounded,
              label: _duration(attachment.durationMs!)),
        ),
      // the recipient sees how long is left once they've opened it
      if (!fromMe && expiresAt != null)
        Positioned(
          left: 10,
          bottom: 10,
          child: _Chip(
              key: const Key('expiresIn'),
              icon: Icons.timer_outlined,
              label: 'Disappears in ${remainingLabel(expiresAt, now)}'),
        ),
    ]);
  }
}

/// My photo or video going up: the file itself, with progress.
class _Uploading extends StatelessWidget {
  const _Uploading({required this.message, required this.upload});

  final ChatMessage message;
  final LocalUpload upload;

  @override
  Widget build(BuildContext context) {
    final failed = message.failed;
    final processing = upload.progress >= 1;
    return Stack(fit: StackFit.expand, children: [
      if (upload.isVideo)
        const ColoredBox(
          color: HuntrColors.surfaceHigh,
          child: Center(
              child: Icon(Icons.videocam_rounded,
                  size: 48, color: HuntrColors.muted)),
        )
      else
        Image.memory(Uint8List.fromList(upload.bytes),
            fit: BoxFit.cover, gaplessPlayback: true),
      ColoredBox(
          color: failed ? const Color(0x99000000) : const Color(0x66000000)),
      Center(
        child: failed
            ? const Icon(Icons.refresh_rounded,
                size: 40, color: Colors.white, semanticLabel: 'Retry')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    key: const Key('uploadProgress'),
                    value: processing ? null : upload.progress,
                    strokeWidth: 4,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                    processing
                        ? 'Processing…'
                        : 'Uploading ${(upload.progress * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
      ),
    ]);
  }
}

class _Expired extends StatelessWidget {
  const _Expired({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('mediaExpired'),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HuntrColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        const Icon(Icons.timer_off_outlined, color: HuntrColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isVideo ? 'Video expired' : 'Photo expired',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('It can no longer be opened.',
                    style: TextStyle(color: HuntrColors.muted, fontSize: 13)),
              ]),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

String _duration(int ms) {
  final seconds = (ms / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// "23h 5m", "12m", "45s": what's left until [deadline].
String remainingLabel(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  if (left.inSeconds <= 0) return '0s';
  if (left.inHours >= 1) {
    final minutes = left.inMinutes % 60;
    return minutes == 0 ? '${left.inHours}h' : '${left.inHours}h ${minutes}m';
  }
  if (left.inMinutes >= 1) return '${left.inMinutes}m';
  return '${left.inSeconds}s';
}
