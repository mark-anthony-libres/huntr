import 'package:flutter/material.dart';

import '../../screens/nearby_compose_screen.dart' show editNearbyThread;
import '../../screens/nearby_post_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'nearby_post_card.dart';

/// What a list of threads does with one of them (the Threads feed, my
/// anonymous profile's Feed and Reposts): heart it, repost it, open it,
/// open its author, edit, delete or report it - each shown at once and put
/// right by the backend's answer.
mixin ThreadListActions<T extends StatefulWidget> on State<T> {
  /// The threads shown (null: not loaded yet).
  List<NearbyPost>? get threads;
  set threads(List<NearbyPost>? value);

  void replaceThread(NearbyPost post) {
    if (!mounted) return;
    setState(() => threads = [
          for (final p in threads ?? const <NearbyPost>[])
            p.id == post.id ? post : p
        ]);
  }

  void removeThread(int postId) {
    if (!mounted) return;
    setState(() => threads = [
          for (final p in threads ?? const <NearbyPost>[])
            if (p.id != postId) p
        ]);
  }

  void sayAboutThread(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _failed(Object error) => sayAboutThread(
      error is BackendException ? error.message : "That didn't go through.");

  Future<void> likeThread(NearbyPost post) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) return;
    // at once; corrected (or undone) by the answer
    replaceThread(post.copyWith(
        liked: !post.liked, likeCount: post.likeCount + (post.liked ? -1 : 1)));
    try {
      final result = await service.like(token, post.id, like: !post.liked);
      replaceThread(
          post.copyWith(likeCount: result.count, liked: result.liked));
    } catch (error) {
      replaceThread(post);
      _failed(error);
    }
  }

  Future<void> repostThread(NearbyPost post) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) return;
    replaceThread(post.copyWith(
        reposted: !post.reposted,
        repostCount: post.repostCount + (post.reposted ? -1 : 1)));
    try {
      final result =
          await service.repost(token, post.id, repost: !post.reposted);
      replaceThread(
          post.copyWith(repostCount: result.count, reposted: result.reposted));
    } catch (error) {
      replaceThread(post);
      _failed(error);
    }
  }

  /// Its discussion: a deleted or no-longer-visible thread leaves the list;
  /// otherwise its counts.
  Future<void> openThread(NearbyPost post) async {
    final updated = await Navigator.of(context).push<NearbyPost?>(
        MaterialPageRoute(builder: (_) => NearbyPostScreen(post: post)));
    if (!mounted) return;
    updated == null ? removeThread(post.id) : replaceThread(updated);
  }

  /// The author's anonymous profile: Report there reports it here.
  Future<void> openThreadAuthor(NearbyPost post) async {
    final action = await openThreadsAuthor(context,
        author: post.author,
        postId: post.id,
        distanceM: post.distanceM,
        mine: post.mine);
    if (action != null && mounted) await actOnThread(post, action);
  }

  Future<void> actOnThread(NearbyPost post, NearbyAction action) async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) return;
    if (action == NearbyAction.edit) {
      final edited = await editNearbyThread(context, post);
      if (edited != null) replaceThread(edited);
      return;
    }
    try {
      if (action == NearbyAction.delete) {
        if (!await _confirmDelete()) return;
        await service.delete(token, postId: post.id);
        sayAboutThread('Post deleted.');
      } else {
        if (!mounted) return;
        final reason = await askReportReason(context);
        if (reason == null) return;
        await service.report(token, post.id, reason: reason);
        sayAboutThread("Thanks. It's reported, and you won't see it anymore.");
      }
      removeThread(post.id);
    } catch (error) {
      _failed(error);
    }
  }

  Future<bool> _confirmDelete() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this post?'),
          content: const Text('Its comments go with it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            TextButton(
                key: const Key('nearbyConfirmDelete'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete',
                    style: TextStyle(color: HuntrColors.coral))),
          ],
        ),
      ) ??
      false;
}
