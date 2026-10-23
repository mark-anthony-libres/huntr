import 'dart:async';

import 'package:flutter/material.dart';

import '../services/presence/presence_service.dart';
import '../services/services_scope.dart';
import '../state/block_state.dart';
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../state/tap_state.dart';
import 'chats_screen.dart';
import 'explore_screen.dart';
import 'me_screen.dart';
import 'taps_screen.dart';
import '../widgets/huntr_bottom_bar.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // the tabs, in order
  static const _exploreTab = 0;
  static const _chatsTab = 2; // Taps is 1

  int _tab = _exploreTab;
  StreamSubscription<String>? _events;

  // Shown as online while signed in here and the app is in the foreground.
  PresenceService? _presence;
  MessagingState? _messaging;
  TapState? _taps;
  AppLifecycleListener? _lifecycle;

  /// A live event: chats and taps each take what concerns them.
  void _handleEvent(Map<String, dynamic> event) {
    _messaging?.handleEvent(event);
    _taps?.handleEvent(event);
  }

  /// Back online: messages and taps re-sync, and blocks are checked again.
  Future<void> _reconnected() async {
    unawaited(_taps?.refresh());
    await _messaging?.sync();
    if (mounted) await BlockScope.read(context)?.checkAll();
  }

  /// Someone blocked me, or lifted it (or I did, elsewhere): their status
  /// from the backend, and Explore's cached list follows it.
  Future<void> _blockChanged(int userId) async {
    final blocks = BlockScope.read(context);
    final app = AppScope.read(context);
    final status = await blocks?.check(userId);
    if (status == null) return;
    status.blocked ? app.block('user-$userId') : app.unblock('user-$userId');
  }

  /// HUNTR was really in the background (not just covered by a system
  /// popup, like a permission request: re-syncing on each of those flooded
  /// the server into its rate limit).
  bool _wasHidden = false;

  void _foreground() {
    if (!_wasHidden) return;
    _wasHidden = false;
    _presence?.setForeground(true);
    _messaging?.setForeground(true);
    unawaited(_messaging?.sync());
    unawaited(_taps?.refresh());
    unawaited(BlockScope.read(context)?.checkAll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = AppScope.read(context).sessionToken;
    _presence ??= ServicesScope.presenceOf(context);
    _messaging ??= MessagingScope.read(context);
    _taps ??= TapScope.read(context);
    if (token != null && _lifecycle == null) {
      // Chat events come on the presence connection; after it (re)connects,
      // and when the app comes back to the foreground, messages re-sync.
      _presence
        ?..onEvent = _handleEvent
        ..onConnected = _reconnected
        ..start(token);
      _messaging?.onBlockChanged = _blockChanged;
      // after this frame: refreshing marks the chat list as loading, which
      // can't happen while this screen is being built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_messaging?.refresh());
        unawaited(_taps?.refresh());
      });
      _lifecycle = AppLifecycleListener(
        onShow: _foreground,
        onResume: _foreground,
        onHide: () {
          _wasHidden = true;
          _presence?.setForeground(false);
          _messaging?.setForeground(false);
        },
      );
    }
    // Show request answers wherever the user is, with a shortcut to the chat.
    _events ??= AppScope.read(context).events.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          action: SnackBarAction(
              label: 'Chats',
              onPressed: () => setState(() => _tab = _chatsTab)),
        ));
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _presence
      ?..onEvent = null
      ..onConnected = null
      ..stop(); // signed out (this screen only exists while signed in)
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messaging = MessagingScope.of(context);
    final unread = messaging?.unreadTotal ?? AppScope.of(context).chatsBadge;
    final taps = TapScope.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const ExploreScreen(),
          const TapsScreen(),
          ChatsScreen(onExplore: () => setState(() => _tab = _exploreTab)),
          const MeScreen(),
        ],
      ),
      bottomNavigationBar: HuntrBottomBar(
        selectedIndex: _tab,
        onSelected: (i) => setState(() => _tab = i),
        items: [
          const HuntrBottomBarItem(
              icon: Icons.explore_outlined, label: 'Explore'),
          HuntrBottomBarItem(
              icon: Icons.waving_hand_outlined,
              label: 'Taps',
              // unread taps and new viewers, both under Taps
              badge: (taps?.unreadCount ?? 0) + (taps?.newViewers ?? 0)),
          HuntrBottomBarItem(
              icon: Icons.chat_bubble_outline, label: 'Chats', badge: unread),
          const HuntrBottomBarItem(icon: Icons.person_outline, label: 'Me'),
        ],
      ),
    );
  }
}
