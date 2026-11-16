import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/tap_service.dart';

/// My Tap inbox, kept up to date: loaded when signed in, again when a tap
/// arrives (the backend's `tap.new`) or leaves (`taps.changed`: someone I
/// tapped answered mine to them), when a block or unmatch changes (their
/// taps are hidden) and after the live connection comes back. Also how I tap
/// someone. The backend enforces every rule; this only shows them.
///
/// And the Viewers tab: who viewed my profile in the last 24 hours, loaded
/// when it's opened, again when someone views it (`profile.viewed`) or a
/// block or unmatch changes; and recording my own visits to profiles.
/// Someone just tapped me, or viewed my profile: shown for a moment beside
/// the Taps button. [person] is null when who it was isn't known (then a
/// blank portrait).
class TapActivity {
  const TapActivity(
      {required this.serial, required this.viewed, required this.person});

  /// Each new one has a bigger number (to tell it from the last).
  final int serial;

  /// A profile view (false: a tap).
  final bool viewed;
  final Profile? person;
}

class TapState extends ChangeNotifier {
  TapState(
      {required this.service, required this.token, this.onSessionRejected});

  final TapService service;
  final String? Function() token;
  final VoidCallback? onSessionRejected;

  List<ReceivedTap>? _taps;
  bool _loading = false;
  String? _error;

  /// The taps waiting for me (null: not loaded yet): latest tapped first,
  /// or ([byCount]) most taps first, then latest.
  List<ReceivedTap>? get taps {
    final taps = _taps;
    if (taps == null || !_byCount) return taps;
    return [...taps]..sort((a, b) => a.count != b.count
        ? b.count.compareTo(a.count)
        : b.receivedAt.compareTo(a.receivedAt));
  }

  bool _byCount = false;

  /// The inbox sorted by how many taps (false: by the latest, the default).
  bool get byCount => _byCount;

  void sortByCount(bool byCount) {
    if (_byCount == byCount) return;
    _byCount = byCount;
    notifyListeners();
  }

  bool get loading => _loading;

  /// Why the inbox couldn't load (null: it did, or hasn't tried).
  String? get error => _error;

  /// Taps I haven't opened yet (the Taps tab's badge).
  int get unreadCount => _taps?.where((t) => !t.isRead).length ?? 0;

  // ---- what just happened, for the bubble beside Taps ----

  TapActivity? _activity;
  int _activitySerial = 0;

  /// The latest tap or view that came in live (null: none yet).
  TapActivity? get latestActivity => _activity;

  void _announce({required bool viewed, Profile? person}) {
    _activity =
        TapActivity(serial: ++_activitySerial, viewed: viewed, person: person);
    notifyListeners();
  }

  /// Who just tapped me: the new tap in the reloaded inbox.
  Future<void> _tapArrived(Object? tapId) async {
    await refresh();
    Profile? sender;
    for (final t in _taps ?? const <ReceivedTap>[]) {
      if (t.id == tapId) sender = t.sender;
    }
    _announce(viewed: false, person: sender);
  }

  /// Who just viewed me: the latest of my viewers, if that visit is just
  /// now (otherwise it isn't known who: a blank portrait).
  Future<void> _viewArrived() async {
    final current = token();
    if (current == null) return;
    Profile? viewer;
    try {
      // the opened list was just loaded again; otherwise the first page
      final latest = _viewers != null
          ? (await refreshViewers().then((_) => _viewers))?.firstOrNull
          : (await service.fetchViewers(current)).viewers.firstOrNull;
      if (latest != null &&
          DateTime.now().difference(latest.lastViewedAt).abs() <
              const Duration(minutes: 2)) {
        viewer = latest.person;
      }
    } on SessionRejectedException {
      onSessionRejected?.call();
      return;
    } catch (error) {
      debugPrint('Latest viewer not loaded: $error');
    }
    _announce(viewed: true, person: viewer);
  }

  /// Asked to open the Viewers part of Taps (e.g. from the bubble); taken
  /// once by the Taps screen.
  bool _viewersWanted = false;

  void openViewers() {
    _viewersWanted = true;
    notifyListeners();
  }

  bool takeViewersRequest() {
    final wanted = _viewersWanted;
    _viewersWanted = false;
    return wanted;
  }

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

  int _newViewers = 0;

  /// People who viewed my profile since I last opened Viewers (its badge).
  int get newViewers => _newViewers;

  /// The new viewers' count from the backend (with the inbox, and when
  /// someone views me).
  Future<void> refreshNewViewers() async {
    final current = token();
    if (current == null) return;
    try {
      final count = await service.fetchNewViewerCount(current);
      if (count == _newViewers) return;
      _newViewers = count;
      notifyListeners();
    } on SessionRejectedException {
      onSessionRejected?.call();
    } catch (error) {
      debugPrint('New viewers not counted: $error');
    }
  }

  /// I opened Viewers: nobody in it is new anymore.
  Future<void> markViewersSeen() async {
    final current = token();
    if (current == null) return;
    if (_newViewers != 0) {
      _newViewers = 0;
      notifyListeners();
    }
    try {
      await service.markViewersSeen(current);
    } on SessionRejectedException {
      onSessionRejected?.call();
    } catch (error) {
      debugPrint('Viewers not marked seen: $error');
    }
  }

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

  /// The inbox (and the new viewers' count) again.
  Future<void> refresh() async {
    final current = token();
    if (current == null) return;
    unawaited(refreshNewViewers());
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
      // a new tap: the inbox, and who it was beside Taps
      case 'tap.new':
        unawaited(_tapArrived(event['tap_id']));
      case 'taps.changed':
        unawaited(refresh());
      case 'block.changed' || 'unmatch.changed':
        unawaited(refresh());
        if (_viewers != null) unawaited(refreshViewers());
      // someone viewed my profile: the badge, and the list if it's been
      // opened
      case 'profile.viewed':
        unawaited(refreshNewViewers());
        // (and the list, when it's been opened)
        unawaited(_viewArrived());
    }
  }

  /// I opened Taps: every tap is read, and the badge clears (the backend
  /// is told once; nothing to do when none is unread).
  Future<void> markAllRead() async {
    final current = token();
    final taps = _taps;
    if (current == null || taps == null || unreadCount == 0) return;
    _taps = [for (final t in taps) t.isRead ? t : t.read()];
    notifyListeners();
    try {
      await service.markAllRead(current);
    } catch (error) {
      debugPrint('Taps not marked read: $error');
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

  /// I tap them (it goes to their Taps inbox, or counts up my waiting tap
  /// there). Throws what the backend says, e.g. too soon after the last.
  Future<void> send(int userId) => service.send(_token(), userId);

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
    _activity = null;
    _viewersWanted = false;
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
