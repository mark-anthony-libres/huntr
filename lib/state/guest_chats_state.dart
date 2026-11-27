import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/guest_chat_api.dart';
import '../services/huntr_backend.dart' show SessionRejectedException;

/// The host's side of guest chats: my guest link, and ending, deleting or
/// blocking a guest chat. The chats themselves are anonymous chats (in
/// [MessagingState]); [onChatsChanged] reloads them after a change, or when
/// a live event says one ended, went or moved.
class GuestChatsState extends ChangeNotifier {
  GuestChatsState(
      {required this.api,
      required this.token,
      this.onSessionRejected,
      this.onChatsChanged});

  final GuestChatApi api;
  final String? Function() token;
  final VoidCallback? onSessionRejected;

  /// Reload the chats (a guest chat ended, was deleted, or moved).
  Future<void> Function()? onChatsChanged;

  GuestLinkInfo? link;

  /// The ready-made story cards (null until loaded).
  List<ReadyStoryCard>? readyCards;

  Future<void> loadReadyCards() async {
    final loaded = await _call(api.storyCards);
    if (loaded != null) {
      readyCards = loaded;
      notifyListeners();
    }
  }

  Future<T?> _call<T>(Future<T> Function(String token) call) async {
    final t = token();
    if (t == null) return null;
    try {
      return await call(t);
    } on SessionRejectedException {
      onSessionRejected?.call();
      return null;
    }
  }

  Future<GuestLinkInfo?> loadLink() async {
    final loaded = await _call(api.myLink);
    if (loaded != null) {
      link = loaded;
      notifyListeners();
    }
    return loaded;
  }

  /// A new link (the old one stops working; its chats end).
  Future<GuestLinkInfo?> newLink() async {
    final made = await _call(api.newLink);
    if (made != null) {
      link = made;
      notifyListeners();
      unawaited(onChatsChanged?.call());
    }
    return made;
  }

  Future<void> setLinkOn(bool on) async {
    final changed = await _call((t) => api.setLinkOn(t, on));
    if (changed != null) {
      link = changed;
      notifyListeners();
    }
  }

  /// Ends a guest chat now: kept to read.
  Future<void> end(int conversationId) async {
    await _call((t) => api.hostEnd(t, conversationId));
    await onChatsChanged?.call();
  }

  /// Deletes a guest chat with everything in it.
  Future<void> delete(int conversationId) async {
    await _call((t) => api.hostDelete(t, conversationId));
    await onChatsChanged?.call();
  }

  /// Deletes it; its guest can't start another one for a day.
  Future<void> block(int conversationId) async {
    await _call((t) => api.block(t, conversationId));
    await onChatsChanged?.call();
  }

  /// A live event: a guest chat ended, went, or its guest joined HUNTR.
  void handleEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (type is String && type.startsWith('guest.')) {
      unawaited(onChatsChanged?.call());
    }
  }

  void clear() {
    link = null;
    readyCards = null;
    notifyListeners();
  }
}

/// [GuestChatsState] for the widgets below (null: no backend, e.g. in tests).
class GuestChatsScope extends InheritedNotifier<GuestChatsState> {
  const GuestChatsScope(
      {super.key, required GuestChatsState? state, required super.child})
      : super(notifier: state);

  static GuestChatsState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuestChatsScope>()?.notifier;

  static GuestChatsState? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GuestChatsScope>()?.notifier;
}
