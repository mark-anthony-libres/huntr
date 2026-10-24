// My anonymous profile (Me > Anonymous profile): my name as others see it,
// and refresh for a new one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/profile_service.dart';
import 'package:huntr/state/app_state.dart';

class _Profiles extends ProfileService {
  AnonymousName name =
      const AnonymousName(name: 'SpicyHamster1234', avatar: 'cat');
  int changes = 0;
  Object? fail;

  @override
  Future<MyProfile> fetchMine(String token) async => MyProfile(
      name: 'Mark',
      displayName: 'Marky',
      age: 21,
      latitude: 14.6,
      longitude: 121,
      lookingFor: const ['chat'],
      onboarded: true,
      anonymousName: name);

  @override
  Future<void> updateLocation(String token, GeoPoint location) async {}

  @override
  Future<AnonymousName> changeAnonymousName(String token) async {
    changes++;
    if (fail != null) throw fail!;
    return name = const AnonymousName(name: 'WittyRaccoon5678', avatar: 'fox');
  }
}

Future<AppState> _openMe(WidgetTester tester, _Profiles profiles) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState()..startSession('token');
  await tester.pumpWidget(HuntrApp(
    state: state,
    profiles: profiles,
    locate: () async => const GeoPoint(latitude: 14.6, longitude: 121),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Me'));
  await tester.pumpAndSettle();
  // Me > Anonymous profile: how others see me
  await tester.tap(find.byKey(const Key('openAnonymousProfile')));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('my anonymous name shows on Me, and Change gives a new one',
      (tester) async {
    final profiles = _Profiles();
    final state = await _openMe(tester, profiles);
    expect(find.text('SpicyHamster1234'), findsOneWidget);
    expect(state.anonymousName?.name, 'SpicyHamster1234');

    // asked first: cancelling changes nothing
    await tester.tap(find.byKey(const Key('anonymousNameChange')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(profiles.changes, 0);

    await tester.tap(find.byKey(const Key('anonymousNameChange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('anonymousNameConfirm')));
    await tester.pumpAndSettle();
    expect(profiles.changes, 1);
    expect(find.text('WittyRaccoon5678'), findsOneWidget);
    expect(state.anonymousName?.name, 'WittyRaccoon5678');
    expect(find.text("You're WittyRaccoon5678 now."), findsOneWidget);
  });

  testWidgets('a refused change says why and keeps the name', (tester) async {
    final profiles = _Profiles()
      ..fail = const BackendException(
          'You just changed it. Try again in a few seconds.');
    await _openMe(tester, profiles);
    await tester.tap(find.byKey(const Key('anonymousNameChange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('anonymousNameConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('You just changed it. Try again in a few seconds.'),
        findsOneWidget);
    expect(find.text('SpicyHamster1234'), findsOneWidget);
  });
}
