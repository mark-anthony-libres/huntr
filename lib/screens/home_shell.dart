import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/presence/presence_service.dart';
import '../services/push_notifications.dart';
import '../services/services_scope.dart';
import '../state/block_state.dart';
import '../state/app_state.dart';
import '../state/messaging_state.dart';
import '../state/tap_state.dart';
import 'chat_screen.dart';
import 'chats_screen.dart';
import 'explore_screen.dart';
import 'me_screen.dart';
import 'nearby_screen.dart';
import 'taps_screen.dart';
import '../widgets/huntr_bottom_bar.dart';
import '../widgets/page_title.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // the tabs, in order
  static const _exploreTab = 0; // Threads is 1
  static const _tapsTab = 2;
  static const _chatsTab = 3;

  int _tab = _exploreTab;

  /// How many times each tab has been opened (its title plays each time).
  final _visits = [
    for (var i = 0; i < 5; i++) ValueNotifier(i == _exploreTab ? 1 : 0)
  ];

  /// Opens a tab (a new visit when it wasn't the one shown).
  void _showTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _visits[tab].value++;
  }

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
        // push notifications: this device, and a tapped one's place
        unawaited(PushNotifications.instance
            .start(token, onOpen: _open)
            .then((_) => _offerNotifications()));
        // the website opened from a notification's link
        final linked =
            kIsWeb ? PushTarget.from(Uri.base.queryParameters) : null;
        if (linked != null) unawaited(_open(linked));
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
          action:
              SnackBarAction(label: 'Chats', onPressed: () => _showTab(_chatsTab)),
        ));
    });
  }

  /// A tapped notification: the Taps inbox, or that chat.
  Future<void> _open(PushTarget target) async {
    if (!mounted) return;
    switch (target) {
      case OpenTaps():
        _showTab(_tapsTab);
      case OpenChat(:final conversationId):
        _showTab(_chatsTab);
        final messaging = _messaging;
        if (messaging == null) return;
        if (messaging.summary(conversationId) == null) {
          await messaging.refresh();
        }
        final chat = messaging.summary(conversationId);
        if (chat == null || !mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen.conversation(
                conversationId: conversationId, other: chat.other)));
    }
  }

  /// Once per device, while notifications aren't allowed or refused yet:
  /// offer them (the website's prompt must follow a tap, so it's a button).
  Future<void> _offerNotifications() async {
    final push = PushNotifications.instance;
    final preferences = AppScope.read(context).devicePreferences;
    if (!mounted || !push.undecided || preferences == null) return;
    if (await preferences.readNotificationsOffered() || !mounted) return;
    unawaited(preferences.saveNotificationsOffered());
    final turnOn = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.notifications_active_outlined, size: 40),
            const SizedBox(height: 12),
            const Text("Don't miss a tap or a message",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Get a notification when someone taps you, messages you or '
                'replies to your story. It says who, never what they wrote. '
                'Change it any time in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.4)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('notificationsOfferOn'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Turn on notifications'),
              ),
            ),
            TextButton(
              key: const Key('notificationsOfferLater'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ]),
        ),
      ),
    );
    if (turnOn == true) await push.enable();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    for (final visits in _visits) {
      visits.dispose();
    }
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
          for (final (i, tab) in [
            const ExploreScreen(),
            const ThreadsTab(),
            const TapsScreen(),
            ChatsScreen(onExplore: () => _showTab(_exploreTab)),
            const MeScreen(),
          ].indexed)
            PageVisits(visits: _visits[i], child: tab),
        ],
      ),
      bottomNavigationBar: HuntrBottomBar(
        selectedIndex: _tab,
        onSelected: _showTab,
        items: [
          const HuntrBottomBarItem(
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
              label: 'Explore'),
          // anonymous posts from people around
          const HuntrBottomBarItem(
              icon: Icons.forum_outlined,
              selectedIcon: Icons.forum_rounded,
              label: 'Threads'),
          HuntrBottomBarItem(
              icon: Icons.waving_hand_outlined,
              selectedIcon: Icons.waving_hand_rounded,
              label: 'Taps',
              // unread taps and new viewers, both under Taps
              badge: (taps?.unreadCount ?? 0) + (taps?.newViewers ?? 0)),
          HuntrBottomBarItem(
              icon: Icons.chat_bubble_outline,
              selectedIcon: Icons.chat_bubble_rounded,
              label: 'Chats',
              badge: unread),
          const HuntrBottomBarItem(
              icon: Icons.person_outline,
              selectedIcon: Icons.person_rounded,
              label: 'Me'),
        ],
      ),
    );
  }
}
