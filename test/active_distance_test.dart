import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';
import 'package:huntr/widgets/avatar.dart';

/// Someone in a chat, as the backend sends them.
Profile _person({Object? activeUntil, double? distanceKm}) => Profile.nearby({
      'id': 7,
      'display_name': 'Daniel',
      'age': 30,
      'presence': 'offline',
      'active_until': activeUntil,
      'distance_km': distanceKm,
    });

class _Quiet extends MessagingService {
  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      const MessagePage(messages: [], hasMore: false);

  @override
  Future<void> markRead(String token, int conversationId) async {}

  @override
  Future<void> typing(String token, int conversationId, bool active) async {}
}

Future<void> _openChat(WidgetTester tester, Profile other) async {
  await tester.pumpWidget(AppScope(
    state: AppState()..startSession('token'),
    child: MessagingScope(
      state: MessagingState(
          service: _Quiet(), token: () => 'token', playSound: () {}),
      child: MaterialApp(
          theme: buildHuntrTheme(),
          home: ChatScreen.conversation(conversationId: 1, other: other)),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _dot => find.byKey(const Key('recentlyActiveDot'));

void main() {
  group('Recently active', () {
    final until = DateTime(2026, 11, 7, 12, 20);

    test('active until the end of the window, not after', () {
      final p = _person(activeUntil: until.toUtc().toIso8601String());
      // last active 5 minutes ago (window ends in 15)
      expect(p.recentlyActiveAt(until.subtract(const Duration(minutes: 15))),
          isTrue);
      // exactly 20 minutes after the last activity: still active
      expect(p.recentlyActiveAt(until), isTrue);
      // a moment later: not
      expect(
          p.recentlyActiveAt(until.add(const Duration(seconds: 1))), isFalse);
    });

    test('no timestamp (hidden or never seen): not active', () {
      expect(_person().activeUntil, isNull);
      expect(_person().recentlyActiveAt(DateTime.now()), isFalse);
    });

    testWidgets('the blue dot shows while active, bottom left', (tester) async {
      final soon = DateTime.now().add(const Duration(minutes: 10));
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: Avatar(
                  profile: _person(activeUntil: soon.toIso8601String()),
                  size: 56,
                  showOnline: false,
                  showActive: true))));
      expect(_dot, findsOneWidget);
      final avatar = tester.getRect(find.byType(Avatar));
      final dot = tester.getRect(_dot);
      expect(dot.left, avatar.left);
      expect(dot.bottom, avatar.bottom);
      // the avatar keeps its size
      expect(avatar.size, const Size(56, 56));
    });

    testWidgets('no dot once the window has passed, or without a time',
        (tester) async {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      for (final p in [
        _person(activeUntil: past.toIso8601String()),
        _person()
      ]) {
        await tester.pumpWidget(MaterialApp(
            home: Avatar(profile: p, showOnline: false, showActive: true)));
        expect(_dot, findsNothing);
      }
    });

    testWidgets('the dot goes by itself when the window ends', (tester) async {
      await tester.runAsync(() async {
        final end = DateTime.now().add(const Duration(milliseconds: 300));
        await tester.pumpWidget(MaterialApp(
            home: Avatar(
                profile: _person(activeUntil: end.toIso8601String()),
                showOnline: false,
                showActive: true)));
        expect(_dot, findsOneWidget);
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump(const Duration(seconds: 1));
      expect(_dot, findsNothing);
    });
  });

  group('Distance', () {
    test('roughly, and only when they show it', () {
      expect(_person(distanceKm: 2.5).approximateDistanceLabel, '2.5 km away');
      expect(_person(distanceKm: 3.0).approximateDistanceLabel, '3 km away');
      expect(_person(distanceKm: 10.4).approximateDistanceLabel, '10 km away');
      // hidden by them, or no location: nothing
      expect(_person().approximateDistanceLabel, isNull);
    });

    testWidgets('the chat shows the dot and how far they are', (tester) async {
      final soon = DateTime.now().add(const Duration(minutes: 10));
      await _openChat(tester,
          _person(activeUntil: soon.toIso8601String(), distanceKm: 2.5));
      expect(_dot, findsOneWidget);
      expect(find.textContaining('2.5 km away'), findsOneWidget);
    });

    testWidgets('a hidden distance and activity show nothing in the chat',
        (tester) async {
      await _openChat(tester, _person());
      expect(_dot, findsNothing);
      expect(find.textContaining('km away'), findsNothing);
    });
  });
}
