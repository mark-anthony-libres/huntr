import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/huntr_backend.dart';
import '../services/tap_service.dart';

/// My Tap inbox, kept up to date: loaded when signed in, again when a tap
/// arrives (the backend's `tap.new`), when a block or unmatch changes (their
/// taps are hidden) and after the live connection comes back. Also how I tap
/// someone. The backend enforces every rule; this only shows them.
///
/// And the Viewers tab: who viewed my profile in the last 24 hours, loaded
/// when it's opened, again when someone views it (`profile.viewed`) or a
/// block or unmatch changes; and recording my own visits to profiles.
class TapState extends ChangeNotifier {
  TapState(
      {required this.service, required this.token, this.onSessionRejected});

  final TapService service;
  final String? Function() token;
  final VoidCallback? onSessionRejected;

  List<ReceivedTap>? _taps;
  bool _loading = false;
  String? _error;

  /// The taps waiting for me, newest first (null: not loaded yet).
  List<ReceivedTap>? get taps => _taps;
  bool get loading => _loading;

  /// Why the inbox couldn't load (null: it did, or hasn't tried).
  String? get error => _error;

  /// Taps I haven't opened yet (the Taps tab's badge).
  int get unreadCount => _taps?.where((t) => !t.isRead).length ?? 0;

  // ---- my profile's viewers ----

  List<ProfileViewer>? _viewers;
  int? _viewersNext;
  String? _viewersError;
  bool _loadingViewers = false;

  /// Who viewed my profile, latest first (null: not loaded yet).
  List<ProfileViewer>? get viewers => _viewers;

  /// Why they couldn't load (null: they did, or haven't tried).
  String? get viewersError => _viewersError;

  /// More viewers to load as the list is scrolled.
  bool get moreViewers => _viewersNext != null;

  /// The first page again, or ([more]) the next one.
  Future<void> refreshViewers({bool more = false}) async {
    final current = token();
    final offset = more ? _viewersNext : 0;
    if (current == null || offset == null || _loadingViewers) return;
    _loadingViewers = true;
    try {
      final page = await service.fetchViewers(current, offset: offset);
      final known = {
        if (more)
          for (final v in _viewers ?? []) v.person.id
      };
      _viewers = [
        if (more) ...?_viewers,
        for (final v in page.viewers)
          if (!known.contains(v.person.id)) v,
      ];
      _viewersNext = page.nextOffset;
      _viewersError = null;
    } on SessionRejectedException {
      onSessionRejected?.call();
    } catch (error) {
      _viewersError = error is BackendException
          ? error.message
          : 'Check your connection and try again.';
    } finally {
      _loadingViewers = false;
      notifyListeners();
    }
  }

  /// I opened their profile: one call per opening ([visitId] stays the same
  /// for that opening, so a repeat counts once). Never fails loudly.
  Future<void> recordView(int userId, String visitId) async {
    final current = token();
    if (current == null) return;
    try {
      await service.recordView(current, userId, visitId);
    } on SessionRejectedException {
      onSessionRejected?.call();
    } catch (error) {
      debugPrint('Profile view not recorded: $error');
    }
  }

  Future<void> refresh() async {
    final current = token();
    if (current == null) return;
    _loading = true;
    notifyListeners();
    try {
      _taps = await service.fetchInbox(current);
      _error = null;
    } on SessionRejectedException {
      onSessionRejected?.call();
    } catch (error) {
      _error = error is BackendException
          ? error.message
          : 'Check your connection and try again.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// A live event: refreshes the inbox when it concerns taps.
  void handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'tap.new':
        unawaited(refresh());
      case 'block.changed' || 'unmatch.changed':
        unawaited(refresh());
        if (_viewers != null) unawaited(refreshViewers());
      // someone viewed my profile: the list, if it's been opened
      case 'profile.viewed':
        if (_viewers != null) unawaited(refreshViewers());
    }
  }

  /// I opened it (the backend is told once).
  Future<void> markRead(ReceivedTap tap) async {
    final current = token();
    if (current == null || tap.isRead) return;
    _replace(tap.id, (t) => t.read());
    try {
      await service.markRead(current, tap.id);
    } catch (error) {
      debugPrint('Tap not marked read: $error');
    }
  }

  /// I tap them (it goes to their Taps inbox). Throws what the backend says,
  /// e.g. that my earlier tap is still waiting.
  Future<void> send(int userId) => service.send(_token(), userId);

  /// My tap to them is still waiting for their answer (their profile shows
  /// it as tapped).
  Future<bool> isWaiting(int userId) => service.isWaiting(_token(), userId);

  /// My response: the backend starts (or continues) our direct conversation;
  /// the tap leaves my inbox. Throws what the backend says.
  Future<TapResponse> respond(ReceivedTap tap,
      {required String body, required String clientId}) async {
    final response =
        await service.respond(_token(), tap.id, body: body, clientId: clientId);
    _taps = [...?_taps?.where((t) => t.id != tap.id)];
    notifyListeners();
    return response;
  }

  void clear() {
    _taps = null;
    _error = null;
    _viewers = null;
    _viewersNext = null;
    _viewersError = null;
    notifyListeners();
  }

  String _token() {
    final current = token();
    if (current == null) throw const SessionRejectedException();
    return current;
  }

  void _replace(int id, ReceivedTap Function(ReceivedTap) change) {
    final taps = _taps;
    if (taps == null) return;
    _taps = [for (final t in taps) t.id == id ? change(t) : t];
    notifyListeners();
  }
}

/// Gives [TapState] to the screens below (null: no taps, e.g. tests and
/// sample data).
class TapScope extends InheritedNotifier<TapState> {
  const TapScope({super.key, required TapState? state, required super.child})
      : super(notifier: state);

  static TapState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TapScope>()?.notifier;

  static TapState? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TapScope>()?.notifier;
}
