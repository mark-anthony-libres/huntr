import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/screens/live_location_screen.dart';
import 'package:huntr/services/device_location.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/location_service.dart' show LocationException;
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';

final _t0 = DateTime(2026, 10, 20, 12);

typedef LatLngCenter = (double, double);

Profile _person(int id, {String name = 'Sam'}) => Profile.nearby({
      'id': id,
      'display_name': name,
      'age': 30,
      'presence': 'online',
    });

/// One live location session (message 50) in conversation 1 with person 7,
/// as the backend would answer me.
class _FakeLive extends MessagingService {
  _FakeLive({required this.iAsked, this.status = 'pending'});

  final bool iAsked;
  String status;
  String? endReason;
  bool? endedByMe;
  final List<String> calls = [];
  final List<(double, double)> sent = [];
  int beats = 0;
  bool rejectPositions = false;

  /// Holds a stop until completed (the request is still in flight).
  Completer<void>? stopGate;

  ChatMessage get message => ChatMessage(
        id: 50,
        conversationId: 1,
        fromMe: iAsked,
        body: '',
        sentAt: _t0,
        type: ChatMessageType.liveLocation,
        liveLocation: LiveLocationInfo(
          status: status,
          requestedByMe: iAsked,
          canAccept: status == 'pending' && !iAsked,
          canCancel: status == 'pending' && iAsked,
          canStop: status == 'active',
          endReason: endReason,
          endedByMe: endedByMe,
          heartbeat: const Duration(seconds: 20),
        ),
      );

  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      MessagePage(messages: after == null ? [message] : [], hasMore: false);

  @override
  Future<ChatMessage> fetchMessage(String token, int messageId) async =>
      message;

  @override
  Future<void> markRead(String token, int conversationId) async {}

  @override
  Future<void> typing(String token, int conversationId, bool active) async {}

  @override
  Future<ChatMessage> requestLiveLocation(String token,
      {required int recipientId,
      required String clientId,
      int? replyToId}) async {
    calls.add('request $recipientId');
    status = 'pending';
    return message;
  }

  @override
  Future<ChatMessage> liveLocationAction(
      String token, int messageId, String action,
      {String? reason}) async {
    calls.add(reason == null ? action : '$action $reason');
    if (action == 'stop' && stopGate != null) await stopGate!.future;
    status = switch (action) {
      'accept' => 'active',
      'decline' => 'declined',
      'cancel' => 'cancelled',
      _ => 'ended',
    };
    if (action == 'stop') {
      endReason = reason ?? 'stopped';
      endedByMe = true;
    }
    return message;
  }

  @override
  Future<void> sendLivePosition(String token, int messageId,
      {required double latitude,
      required double longitude,
      double? accuracy}) async {
    if (rejectPositions) {
      status = 'ended';
      endReason = 'offline';
      endedByMe = true;
      throw const BackendException('This live location has ended.');
    }
    sent.add((latitude, longitude));
  }

  @override
  Future<void> liveHeartbeat(String token, int messageId) async => beats++;

  @override
  Future<LivePositions> fetchLivePositions(String token, int messageId) async =>
      const LivePositions();
}

/// The device's position, moved by the test.
class _FakeDevice extends DeviceLocation {
  _FakeDevice({this.denied = false});

  bool denied;
  int reads = 0;
  final moves = StreamController<DevicePosition>.broadcast();

  @override
  Future<DevicePosition> current() async {
    reads++;
    if (denied) {
      throw const LocationException(
          'Huntr needs your location to share it in this chat.');
    }
    return const DevicePosition(latitude: 14.6, longitude: 121.0);
  }

  @override
  Stream<DevicePosition> watch({int minDistance = 25}) => moves.stream;
}

MessagingState _state(_FakeLive service, _FakeDevice device) => MessagingState(
    service: service, token: () => 'token', playSound: () {}, location: device);

Widget _app(MessagingState messaging, Widget home) => AppScope(
      state: AppState()..startSession('token'),
      child: MessagingScope(
        state: messaging,
        child: MaterialApp(theme: buildHuntrTheme(), home: home),
      ),
    );

Map<String, dynamic> _position(double lat, double lng) => {
      'type': 'live_location.position',
      'conversation_id': 1,
      'message_id': 50,
      'latitude': lat,
      'longitude': lng,
    };

const _ended = {
  'type': 'live_location.ended',
  'conversation_id': 1,
  'message_id': 50,
};

void main() {
  group('Live location state', () {
    testWidgets('a request shares nothing until it is accepted',
        (tester) async {
      final service = _FakeLive(iAsked: true);
      final device = _FakeDevice();
      final state = _state(service, device);
      await state.requestLiveLocation(1, _person(7));
      await tester.pump(const Duration(minutes: 1));

      expect(service.calls, ['request 7']);
      expect(state.messagesOf(1).single.liveLocation!.pending, isTrue);
      expect(state.liveSessionIn(1), isNull);
      expect(device.reads, 0);
      expect(service.sent, isEmpty);
      // their position isn't taken while nothing is shared
      state.handleEvent(_position(14.7, 121.1));
      expect(state.livePositionsOf(50).them, isNull);
      state.clear();
    });

    testWidgets(
        'once accepted: sends my position, heartbeats, and shows theirs',
        (tester) async {
      final service = _FakeLive(iAsked: false);
      final device = _FakeDevice();
      final state = _state(service, device);
      await state.load(1);
      await state.acceptLiveLocation(state.messagesOf(1).single);
      await tester.pump();

      expect(state.liveSessionIn(1)?.id, 50);
      expect(service.sent, [(14.6, 121.0)]);
      expect(state.livePositionsOf(50).me?.latitude, 14.6);

      await tester.pump(const Duration(seconds: 41));
      expect(service.beats, 2);

      state.handleEvent(_position(14.7, 121.1));
      expect(state.livePositionsOf(50).them?.latitude, 14.7);
      state.clear();
    });

    testWidgets('moves are sent at most every 10 s, the newest one last',
        (tester) async {
      final service = _FakeLive(iAsked: false, status: 'active');
      final device = _FakeDevice();
      final state = _state(service, device);
      await state.load(1);
      await tester.pump();
      expect(service.sent, hasLength(1));

      // a few metres: not worth sending
      device.moves
          .add(const DevicePosition(latitude: 14.60001, longitude: 121));
      await tester.pump();
      // two real moves inside the cooldown: only the newest goes, after it
      device.moves.add(const DevicePosition(latitude: 14.601, longitude: 121));
      device.moves.add(const DevicePosition(latitude: 14.602, longitude: 121));
      await tester.pump();
      expect(service.sent, hasLength(1));
      await tester.pump(const Duration(seconds: 10));
      expect(service.sent.last, (14.602, 121.0));
      expect(service.sent, hasLength(2));
      state.clear();
    });

    testWidgets('when they stop it, my sharing stops at once', (tester) async {
      final service = _FakeLive(iAsked: true, status: 'active');
      final device = _FakeDevice();
      final state = _state(service, device);
      await state.load(1);
      await tester.pump();
      expect(state.liveSessionIn(1), isNotNull);

      service
        ..status = 'ended'
        ..endReason = 'stopped'
        ..endedByMe = false;
      state.handleEvent(_ended);
      await tester.pump();
      expect(state.liveSessionIn(1), isNull);
      expect(state.livePositionsOf(50).me, isNull);
      expect(state.messagesOf(1).single.liveLocation!.status, 'ended');

      // no more positions or heartbeats, and it doesn't come back
      final beats = service.beats;
      device.moves.add(const DevicePosition(latitude: 15, longitude: 121));
      await tester.pump(const Duration(minutes: 1));
      expect(service.beats, beats);
      expect(service.sent, hasLength(1));
      await state.load(1);
      expect(state.liveSessionIn(1), isNull);
    });

    testWidgets('location access denied: it ends safely for both',
        (tester) async {
      final service = _FakeLive(iAsked: false);
      final device = _FakeDevice(denied: true);
      final state = _state(service, device);
      await state.load(1);
      await state.acceptLiveLocation(state.messagesOf(1).single);
      await tester.pump();

      expect(service.calls, ['accept', 'stop permission']);
      expect(service.sent, isEmpty);
      expect(state.liveSessionIn(1), isNull);
      expect(state.liveProblem, contains('needs your location'));
      expect(state.messagesOf(1).single.liveLocation!.endReason, 'permission');
    });

    testWidgets(
        'denied location, and a still-active copy arrives mid-stop: one stop',
        (tester) async {
      final service = _FakeLive(iAsked: false)..stopGate = Completer();
      final device = _FakeDevice(denied: true);
      final state = _state(service, device);
      await state.load(1);
      final accepting = state.acceptLiveLocation(state.messagesOf(1).single);
      await tester.pump();
      // the accept's "message updated" event: fetched while the stop waits
      state.handleEvent(
          {'type': 'message.updated', 'conversation_id': 1, 'message_id': 50});
      await tester.pump();
      await tester.pump();
      service.stopGate!.complete();
      await accepting;
      await tester.pump();

      expect(service.calls, ['accept', 'stop permission']);
      expect(device.reads, 1);
      expect(state.liveSessionIn(1), isNull);
    });

    testWidgets('location access revoked while sharing ends it',
        (tester) async {
      final service = _FakeLive(iAsked: true, status: 'active');
      final device = _FakeDevice();
      final state = _state(service, device);
      await state.load(1);
      await tester.pump();

      device.moves.addError(const LocationException('Location is turned off.'));
      await tester.pump();
      expect(service.calls, ['stop permission']);
      expect(state.liveSessionIn(1), isNull);
      expect(state.liveProblem, 'Location is turned off.');
    });

    testWidgets('the backend says it ended (e.g. offline): stops locally',
        (tester) async {
      final service = _FakeLive(iAsked: true, status: 'active')
        ..rejectPositions = true;
      final device = _FakeDevice();
      final state = _state(service, device);
      await state.load(1);
      await tester.pump();
      await tester.pump();

      expect(state.liveSessionIn(1), isNull);
      expect(state.messagesOf(1).single.liveLocation!.endReason, 'offline');
    });
  });

  group('Live location UI', () {
    testWidgets(
        'they ask, I accept, the banner shows, and Stop ends it for both',
        (tester) async {
      final service = _FakeLive(iAsked: false);
      final state = _state(service, _FakeDevice());
      await tester.pumpWidget(_app(state,
          ChatScreen.conversation(conversationId: 1, other: _person(7))));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Sam wants to share live locations with you'),
          findsOneWidget);
      expect(find.byKey(const Key('liveBanner')), findsNothing);

      await tester.tap(find.byKey(const Key('acceptLive-50')));
      await tester.pump();
      await tester.pump();
      expect(find.text('You’re sharing a live connection'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stopLiveBanner')));
      await tester.pump();
      await tester.pump();
      expect(service.calls, ['accept', 'stop']);
      expect(find.byKey(const Key('liveBanner')), findsNothing);
      expect(find.text('You stopped sharing.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.clear();
    });

    testWidgets('my request waits, and can be cancelled', (tester) async {
      final service = _FakeLive(iAsked: true);
      final state = _state(service, _FakeDevice());
      await tester.pumpWidget(_app(state,
          ChatScreen.conversation(conversationId: 1, other: _person(7))));
      await tester.pump();
      await tester.pump();

      expect(find.text('Waiting for Sam to accept…'), findsOneWidget);
      expect(find.byKey(const Key('acceptLive-50')), findsNothing);
      await tester.tap(find.byKey(const Key('cancelLive-50')));
      await tester.pump();
      expect(service.calls, ['cancel']);
      expect(find.text('Request cancelled.'), findsOneWidget);
    });

    testWidgets('a waiting request has a banner on top for both of us',
        (tester) async {
      // mine: "You're requesting…" with Cancel request
      final mine = _FakeLive(iAsked: true);
      final state = _state(mine, _FakeDevice());
      await tester.pumpWidget(_app(state,
          ChatScreen.conversation(conversationId: 1, other: _person(7))));
      await tester.pump();
      await tester.pump();
      expect(find.text('You’re requesting to share live locations with Sam'),
          findsOneWidget);
      expect(find.byKey(const Key('acceptLiveBanner')), findsNothing);
      await tester.tap(find.byKey(const Key('cancelLiveBanner')));
      await tester.pump();
      expect(mine.calls, ['cancel']);
      expect(find.byKey(const Key('pendingLiveBanner')), findsNothing);

      // theirs: Accept from the banner starts sharing
      await tester.pumpWidget(const SizedBox());
      final theirs = _FakeLive(iAsked: false);
      final other = _state(theirs, _FakeDevice());
      await tester.pumpWidget(_app(other,
          ChatScreen.conversation(conversationId: 1, other: _person(7))));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sam wants to share live locations'), findsOneWidget);
      expect(find.byKey(const Key('cancelLiveBanner')), findsNothing);
      await tester.tap(find.byKey(const Key('acceptLiveBanner')));
      await tester.pump();
      await tester.pump();
      expect(theirs.calls, ['accept']);
      expect(find.byKey(const Key('pendingLiveBanner')), findsNothing);
      expect(find.byKey(const Key('liveBanner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      other.clear();
    });

    testWidgets('the map shows both of us, and says when it ended',
        (tester) async {
      final service = _FakeLive(iAsked: true, status: 'active');
      final state = _state(service, _FakeDevice());
      await state.load(1);
      await tester.pumpWidget(_app(
          state,
          LiveLocationScreen(
              message: state.messagesOf(1).single,
              me: _person(1, name: 'Me'),
              other: _person(7))));
      await tester.pump();

      expect(find.byKey(const Key('liveConnectionBanner')), findsOneWidget);
      expect(find.text('You · just now'), findsOneWidget);
      expect(find.text('Sam · waiting for location…'), findsOneWidget);
      state.handleEvent(_position(14.7, 121.1));
      await tester.pump();
      expect(find.text('Sam · just now'), findsOneWidget);

      service
        ..status = 'ended'
        ..endReason = 'offline'
        ..endedByMe = false;
      state.handleEvent(_ended);
      await tester.pump();
      await tester.pump();
      expect(find.text('Live sharing ended because Sam went offline.'),
          findsOneWidget);
      expect(find.byKey(const Key('liveConnectionBanner')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a person’s chip centres the map on them',
        (tester) async {
      final service = _FakeLive(iAsked: true, status: 'active');
      final state = _state(service, _FakeDevice());
      await state.load(1);
      await tester.pumpWidget(_app(
          state,
          LiveLocationScreen(
              message: state.messagesOf(1).single,
              me: _person(1, name: 'Me'),
              other: _person(7))));
      await tester.pump();
      state.handleEvent(_position(14.75, 121.12));
      await tester.pump();
      await tester.pump();

      LatLngCenter center() {
        final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
        final c = map.mapController!.camera.center;
        return (c.latitude, c.longitude);
      }

      await tester.tap(find.byKey(const Key('centerThem')));
      await tester.pump();
      expect(center().$1, closeTo(14.75, 1e-6));
      expect(center().$2, closeTo(121.12, 1e-6));
      await tester.tap(find.byKey(const Key('centerMe')));
      await tester.pump();
      expect(center().$1, closeTo(14.6, 1e-6));
      expect(center().$2, closeTo(121.0, 1e-6));
      await tester.pumpWidget(const SizedBox());
      state.clear();
    });
  });
}
