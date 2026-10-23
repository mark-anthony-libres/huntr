import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'media_permission.dart';

import '../models/models.dart';
import '../screens/album_trade_screen.dart';
import '../services/huntr_backend.dart';
import '../services/location_service.dart' show LocationException;
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../theme.dart';
import '../widgets/chat/media_confirm_screen.dart';
import '../widgets/photos/photo_file_check.dart';

/// Where chat photos and videos come from: the device's library and camera
/// (image_picker). Tests swap in their own.
class ChatMediaPicker {
  const ChatMediaPicker();

  static ChatMediaPicker instance = const ChatMediaPicker();

  Future<XFile?> pickImage() =>
      ImagePicker().pickImage(source: ImageSource.gallery);

  Future<XFile?> pickVideo() =>
      ImagePicker().pickVideo(source: ImageSource.gallery);

  bool get hasCamera => ImagePicker().supportsImageSource(ImageSource.camera);

  Future<XFile?> takePhoto() =>
      ImagePicker().pickImage(source: ImageSource.camera);

  Future<XFile?> recordVideo({Duration? maxDuration}) => ImagePicker()
      .pickVideo(source: ImageSource.camera, maxDuration: maxDuration);
}

/// The + menu next to the message box. With [onGif] (phones, where the
/// composer has no room for a separate GIF button) it offers GIFs too.
Future<void> showAttachMenu(BuildContext context,
    {required int conversationId,
    required Profile recipient,
    VoidCallback? onGif}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    // scrolls on short screens instead of overflowing
    isScrollControlled: true,
    builder: (context) => SafeArea(
        child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (key, icon, title, subtitle) in [
            if (onGif != null)
              (
                'gif',
                Icons.gif_box_outlined,
                'GIF or sticker',
                'Search GIPHY',
              ),
            (
              'trade',
              Icons.swap_horiz_rounded,
              'Trade album',
              'Offer one of your private albums'
            ),
            (
              'image',
              Icons.photo_outlined,
              'Send image',
              'From your photo library'
            ),
            (
              'video',
              Icons.videocam_outlined,
              'Send video',
              'From your library'
            ),
            (
              'location',
              Icons.location_on_outlined,
              'Share location',
              'Where you are now, or live with them'
            ),
            (
              'camera',
              Icons.photo_camera_outlined,
              'Open camera',
              'Take a photo or record a video'
            ),
          ])
            ListTile(
              key: Key('attach-$key'),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HuntrColors.orange.withValues(alpha: 0.14),
                ),
                child: Icon(icon, color: HuntrColors.orange),
              ),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(subtitle,
                  style: const TextStyle(color: HuntrColors.muted)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              onTap: () => Navigator.of(context).pop(key),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Photos and videos disappear a while after they’re first opened.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HuntrColors.muted, fontSize: 13),
            ),
          ),
        ]),
      ),
    )),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'gif':
      onGif?.call();
    case 'trade':
      await offerAlbumTrade(context,
          conversationId: conversationId, recipient: recipient);
    case 'image':
      await _send(context, conversationId, recipient,
          () => ChatMediaPicker.instance.pickImage());
    case 'video':
      await _send(context, conversationId, recipient,
          () => ChatMediaPicker.instance.pickVideo());
    case 'camera':
      await _camera(context, conversationId, recipient);
    case 'location':
      await _location(context, conversationId, recipient);
  }
}

// ---- locations ----

/// Sends where I am now (once), or asks them to share live locations both
/// ways (nothing is shared until they accept). Positions are never stored.
Future<void> _location(
    BuildContext context, int conversationId, Profile recipient) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
        child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          key: const Key('location-now'),
          leading: const Icon(Icons.place_outlined, color: HuntrColors.orange),
          title: const Text('Send current location',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Where you are right now',
              style: TextStyle(color: HuntrColors.muted)),
          onTap: () => Navigator.of(context).pop('now'),
        ),
        ListTile(
          key: const Key('location-live'),
          leading: const Icon(Icons.share_location_rounded,
              color: HuntrColors.orange),
          title: const Text('Share live location',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Ask to see each other on a map until one of you stops',
              style: TextStyle(color: HuntrColors.muted)),
          onTap: () => Navigator.of(context).pop('live'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Only the two of you see it. It’s never saved, and either of '
            'you can stop live sharing any time.',
            style: TextStyle(color: HuntrColors.muted, fontSize: 13),
          ),
        ),
      ]),
    )),
  );
  if (choice == null || !context.mounted) return;
  final messaging = MessagingScope.read(context)!;
  final live = choice == 'live';
  if (!live) _say(context, 'Finding your location…');
  try {
    if (live) {
      await messaging.requestLiveLocation(conversationId, recipient);
    } else {
      await messaging.shareLocation(conversationId, recipient);
    }
    if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
  } on LocationException catch (error) {
    if (context.mounted) _say(context, error.message);
  } on BackendException catch (error) {
    if (context.mounted) _say(context, error.message);
  } catch (_) {
    if (context.mounted) {
      _say(
          context,
          live
              ? 'Live location couldn’t be requested. Please try again.'
              : 'Your location couldn’t be shared. Please try again.');
    }
  }
}

// ---- album trades ----

/// Offers one of my albums (full-screen choice; see [AlbumTradeScreen]).
Future<void> offerAlbumTrade(BuildContext context,
    {required int conversationId, required Profile recipient}) async {
  final messaging = MessagingScope.read(context)!;
  // one id per album chosen, so a retried offer is stored once
  final clientIds = <String, String>{};
  await Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AlbumTradeScreen(
      title: 'Trade an album',
      intro: 'Choose an album to offer ${_name(recipient)}. They can pick '
          'one of theirs in return.',
      sendingLabel: 'Offering',
      onChosen: (album) => messaging.offerAlbum(
          conversationId, recipient, int.parse(album.id),
          clientId: clientIds.putIfAbsent(album.id, messaging.newClientId)),
    ),
  ));
}

/// Answers a trade offered to me with one of my albums.
Future<void> answerAlbumTrade(BuildContext context,
    {required int conversationId,
    required Profile sender,
    required AlbumTrade trade}) async {
  final messaging = MessagingScope.read(context)!;
  final offered = trade.offeredAlbum?.name;
  await Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AlbumTradeScreen(
      title: 'Trade back',
      intro: offered == null
          ? 'Choose one of your albums to trade back.'
          : '${_name(sender)} offered “$offered”. Choose one of your albums '
              'to trade back.',
      sendingLabel: 'Trading',
      onChosen: (album) =>
          messaging.respondToTrade(conversationId, trade, int.parse(album.id)),
    ),
  ));
}

String _name(Profile p) => p.name.isEmpty ? 'them' : p.name;

// ---- photos and videos ----

Future<void> _camera(
    BuildContext context, int conversationId, Profile recipient) async {
  final picker = ChatMediaPicker.instance;
  if (!picker.hasCamera) {
    _say(context, 'There’s no camera available on this device.');
    return;
  }
  final mode = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          key: const Key('camera-photo'),
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          onTap: () => Navigator.of(context).pop('photo'),
        ),
        ListTile(
          key: const Key('camera-video'),
          leading: const Icon(Icons.videocam_outlined),
          title: const Text('Record a video'),
          onTap: () => Navigator.of(context).pop('video'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (mode == null || !context.mounted) return;
  final limits = AppScope.read(context).albumLimits;
  await _send(
    context,
    conversationId,
    recipient,
    () => mode == 'photo'
        ? picker.takePhoto()
        : picker.recordVideo(
            maxDuration: limits == null
                ? null
                : Duration(seconds: limits.maxVideoSeconds)),
    confirm: true,
  );
}

/// Picks (or captures), checks, optionally previews (Retake captures again),
/// then sends.
Future<void> _send(BuildContext context, int conversationId, Profile recipient,
    Future<XFile?> Function() pick,
    {bool confirm = false}) async {
  XFile? file;
  List<int> bytes;
  bool isVideo;
  while (true) {
    try {
      // camera / microphone / photos: asks, explains a denial, retries
      file = await withMediaPermission(context, pick);
    } on PlatformException {
      if (context.mounted) _say(context, 'That didn’t work. Please try again.');
      return;
    }
    if (file == null || !context.mounted) return;
    bytes = await file.readAsBytes();
    if (!context.mounted) return;
    isVideo = isVideoFile(bytes);
    final problem = _check(context, bytes, isVideo);
    if (problem != null) {
      _say(context, problem);
      return;
    }
    if (!confirm) break;
    final answer = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          MediaConfirmScreen(bytes: bytes, path: file!.path, isVideo: isVideo),
    ));
    if (!context.mounted || answer == null) return;
    if (answer == 'send') break;
  }
  final messaging = MessagingScope.read(context)!;
  await messaging.sendMedia(
      conversationId,
      recipient,
      LocalUpload(
          bytes: bytes,
          filename: file.name.isEmpty
              ? (isVideo ? 'video.mp4' : 'photo.jpg')
              : file.name,
          isVideo: isVideo));
}

/// Quick checks with the backend's limits (when known); it checks again.
String? _check(BuildContext context, List<int> bytes, bool isVideo) {
  if (bytes.isEmpty) return 'The file is empty.';
  final limits = AppScope.read(context).albumLimits;
  if (isVideo) {
    return limits == null
        ? null
        : checkPickedVideo(bytes, maxBytes: limits.maxVideoBytes);
  }
  return checkPickedPhoto(bytes, maxBytes: limits?.maxPhotoBytes ?? 1 << 40);
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
