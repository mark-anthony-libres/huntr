import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
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
import 'whats_new_screen.dart';
import '../widgets/notifications_off.dart';
import '../widgets/activity_bubble.dart';
import '../widgets/huntr_bottom_bar.dart';
import '../widgets/page_title.dart';
import '../theme.dart';

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
    HomeTabs.current = tab;
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
            .then((_) => _remindNotifications()));
        // the website opened from a notification's link
        final linked =
            kIsWeb ? PushTarget.from(Uri.base.queryParameters) : null;
        if (linked != null) unawaited(_open(linked));
        // What's new: Settings' dot, and news shown once
        unawaited(checkWhatsNew(context));
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
              label: 'Chats', onPressed: () => _showTab(_chatsTab)),
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

  /// Notifications aren't on for HUNTR on this device (never answered, put
  /// off, or blocked): each time the app opens, a screen says so and how to
  /// turn them on.
  Future<void> _remindNotifications() async {
    final status = PushNotifications.instance.permission.value;
    if (!mounted ||
        !PushNotifications.supported ||
        status == null ||
        status == AuthorizationStatus.authorized) {
      return;
    }
    final on = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const NotificationsOffScreen()));
    if (on == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Notifications are on for this device.')));
    }
  }

  @override
  void dispose() {
    if (HomeTabs.show == _showTab) HomeTabs.show = null;
    _lifecycle?.dispose();
    for (final visits in _visits) {
      visits.dispose();
    }
    _presence
      ?..onEvent = null
      ..onConnected = null
      ..stop(); // signed out (this screen only exists while signed in)
    _events?.cancel();
    _bubbleTimer?.cancel();
    super.dispose();
  }

  // ---- the bubble beside Taps: who just tapped me or viewed me ----

  final _tapsAnchor = LayerLink();
  final _bubble = OverlayPortalController();
  TapActivity? _bubbleActivity;
  bool _bubbleVisible = false;
  int _lastActivity = 0;
  Timer? _bubbleTimer;

  /// How long it stays.
  static const _bubbleFor = Duration(seconds: 4);

  /// A new tap or view: shown beside Taps for a moment (not while Taps is
  /// open; the newest replaces the one before).
  void _showActivity(TapActivity? activity) {
    if (activity == null || activity.serial <= _lastActivity) return;
    _lastActivity = activity.serial;
    if (_tab == _tapsTab) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _bubbleActivity = activity;
        _bubbleVisible = true;
      });
      _bubble.show();
      _bubbleTimer?.cancel();
      _bubbleTimer = Timer(_bubbleFor, _hideActivity);
    });
  }

  void _hideActivity() {
    _bubbleTimer?.cancel();
    if (!mounted || !_bubble.isShowing) return;
    setState(() => _bubbleVisible = false);
    // gone once it has faded
    _bubbleTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && !_bubbleVisible) _bubble.hide();
    });
  }

  /// The bubble, tapped: Taps (its Viewers for a view).
  void _openActivity() {
    final activity = _bubbleActivity;
    _hideActivity();
    if (activity == null) return;
    if (activity.viewed) TapScope.read(context)?.openViewers();
    _showTab(_tapsTab);
  }

  /// The bubble beside the Taps button: to its right in the sidebar, above
  /// it on the bottom bar.
  Widget _activityBubble(BuildContext context, {required bool side}) {
    final activity = _bubbleActivity;
    if (activity == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _tapsAnchor,
        showWhenUnlinked: false,
        targetAnchor: side ? Alignment.centerRight : Alignment.topCenter,
        followerAnchor: side ? Alignment.centerLeft : Alignment.bottomCenter,
        offset: side ? const Offset(22, 0) : const Offset(0, -10),
        // smaller on a phone's bottom bar
        child: ActivityBubble(
            activity: activity,
            visible: _bubbleVisible,
            onTap: _openActivity,
            small: !side),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taps = TapScope.of(context);
    _showActivity(taps?.latestActivity);
    // pages opened over this one show the same sidebar (WithHomeSideBar)
    HomeTabs.show = _showTab;
    HomeTabs.current = _tab;
    final tabs = IndexedStack(
      index: _tab,
      children: [
        for (final (i, tab) in [
          const ExploreScreen(),
          const ThreadsTab(),
          const TapsScreen(),
          ChatsScreen(onExplore: () => _showTab(_exploreTab)),
          const MeScreen(),
        ].indexed)
          TabShown(
              shown: i == _tab,
              child: PageVisits(visits: _visits[i], child: tab)),
      ],
    );
    final items = homeTabItems(context, tapsAnchor: _tapsAnchor);
    // the website on a wide screen (a computer, a tablet): the tabs down the
    // left; the app, and the website on a phone: along the bottom
    final side =
        kIsWeb && MediaQuery.sizeOf(context).width >= huntrSideBarMinWidth;
    final Widget page = side
        ? Scaffold(
            body: Row(children: [
              HuntrSideBar(
                  items: items, selectedIndex: _tab, onSelected: _showTab),
              Expanded(child: tabs),
            ]),
          )
        : Scaffold(
            body: tabs,
            bottomNavigationBar: HuntrBottomBar(
                items: items, selectedIndex: _tab, onSelected: _showTab),
          );
    return OverlayPortal(
      controller: _bubble,
      overlayChildBuilder: (context) => _activityBubble(context, side: side),
      child: page,
    );
  }
}

/// The home screen's tabs, as the bottom bar and the sidebar show them
/// (with their badges: unread taps and new viewers, unread chats).
List<HuntrBottomBarItem> homeTabItems(BuildContext context,
    {LayerLink? tapsAnchor}) {
  final messaging = MessagingScope.of(context);
  final unread = messaging?.unreadTotal ?? AppScope.of(context).chatsBadge;
  final taps = TapScope.of(context);
  return [
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
        badge: (taps?.unreadCount ?? 0) + (taps?.newViewers ?? 0),
        anchor: tapsAnchor),
    HuntrBottomBarItem(
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble_rounded,
        label: 'Chats',
        badge: unread),
    const HuntrBottomBarItem(
        icon: Icons.person_outline,
        selectedIcon: Icons.person_rounded,
        label: 'Me'),
  ];
}

/// Which home tab is shown, and how to show another: for a page opened
/// over the home screen that keeps the sidebar ([WithHomeSideBar]).
class HomeTabs {
  HomeTabs._();

  static int current = 0;

  /// Set while the home screen is there.
  static void Function(int tab)? show;
}

/// [child] (a page opened over the home screen) with the home screen's
/// sidebar beside it on a wide screen on the web, as the tabs have it;
/// a tab tapped there closes the page and shows that tab. Elsewhere,
/// [child] alone.
class WithHomeSideBar extends StatelessWidget {
  const WithHomeSideBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final show = HomeTabs.show;
    if (!kIsWeb ||
        show == null ||
        MediaQuery.sizeOf(context).width < huntrSideBarMinWidth) {
      return child;
    }
    return Material(
      color: HuntrColors.night,
      child: Row(children: [
        HuntrSideBar(
          items: homeTabItems(context),
          selectedIndex: HomeTabs.current,
          onSelected: (tab) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            show(tab);
          },
        ),
        Expanded(child: child),
      ]),
    );
  }
}
