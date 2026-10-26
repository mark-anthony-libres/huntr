import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/profile_service.dart';
import 'package:huntr/state/app_state.dart';

const _config = ProfileConfig(
    bioMaxLength: 120, displayNameMaxLength: 50, minAge: 18, maxAge: 99);

MyProfile _profile({
  String? displayName = 'Marky',
  String? bio = 'Hello',
  int age = 31,
  List<String> lookingFor = const ['dates'],
}) =>
    MyProfile(
      name: 'Mark Libres',
      displayName: displayName,
      bio: bio,
      age: age,
      latitude: 14.6,
      longitude: 121,
      lookingFor: lookingFor,
      onboarded: true,
    );

/// The backend, faked: serves a saved profile and records what is saved.
class _FakeProfiles extends ProfileService {
  MyProfile stored = _profile();
  ProfileConfig config = _config;
  Object? failLoadWith;
  Object? failSaveWith;
  final List<ProfileEdit> saved = [];

  @override
  Future<MyProfile> fetchMine(String token) async {
    final failure = failLoadWith;
    if (failure != null) {
      failLoadWith = null; // the next try works
      throw failure;
    }
    return stored;
  }

  @override
  Future<ProfileConfig> fetchConfig(String token) async => config;

  @override
  Future<MyProfile> saveOnboarding(
          String token, OnboardingAnswers answers) async =>
      stored;

  @override
  Future<void> updateLocation(String token, GeoPoint location) async {}

  @override
  Future<MyProfile> updateProfile(String token, ProfileEdit edit) async {
    saved.add(edit);
    if (failSaveWith != null) throw failSaveWith!;
    stored = _profile(
      displayName: edit.displayName.trim().isEmpty ? null : edit.displayName,
      bio: edit.bio.trim().isEmpty ? null : edit.bio,
      age: edit.age,
      lookingFor: [for (final choice in edit.lookingFor) choice.name],
    );
    return stored;
  }
}

Future<AppState> _openEditProfile(WidgetTester tester, _FakeProfiles profiles,
    {void Function()? beforeEdit}) async {
  tester.view.physicalSize = const Size(800, 1600);
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
  beforeEdit?.call();
  await tester.tap(find.byTooltip('Edit profile'));
  await tester.pumpAndSettle();
  return state;
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  testWidgets('the form is filled from the database', (tester) async {
    await _openEditProfile(tester, _FakeProfiles());
    expect(_fieldText(tester, 'editDisplayName'), 'Marky');
    expect(_fieldText(tester, 'editBio'), 'Hello');
    expect(_fieldText(tester, 'editAge'), '31');
    final dates = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, LookingFor.dates.label));
    final chat = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, LookingFor.chat.label));
    expect(dates.selected, isTrue);
    expect(chat.selected, isFalse);
  });

  testWidgets('labels sit outside bordered inputs', (tester) async {
    await _openEditProfile(tester, _FakeProfiles());
    for (final label in [
      'Display name',
      'Bio',
      'Age',
      'Sexual position',
      'Expectation'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Enter your display name'), findsOneWidget); // hint
    final decorators = tester.widgetList<InputDecorator>(find.descendant(
        of: find.byType(Form), matching: find.byType(InputDecorator)));
    expect(decorators, hasLength(3)); // name, bio, age (chips are pills)
    for (final decorator in decorators) {
      final border = decorator.decoration.enabledBorder as OutlineInputBorder;
      expect(border.borderSide.style, BorderStyle.solid);
      expect(border.borderSide.width, greaterThan(0));
      expect(decorator.decoration.labelText, isNull);
    }
  });

  testWidgets('a failed load shows an error and can be retried',
      (tester) async {
    final profiles = _FakeProfiles();
    await _openEditProfile(tester, profiles,
        beforeEdit: () => profiles.failLoadWith =
            const BackendException('Could not reach the server.'));
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.byKey(const Key('editDisplayName')), findsNothing);
    await tester.tap(find.byKey(const Key('editProfileRetry')));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'editDisplayName'), 'Marky');
  });

  testWidgets('the bio limit and counter come from the backend',
      (tester) async {
    await _openEditProfile(tester, _FakeProfiles());
    expect(find.text('5 / 120'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('editBio')), 'x' * 130);
    await tester.pump();
    expect(_fieldText(tester, 'editBio'), 'x' * 120);
    expect(find.text('120 / 120'), findsOneWidget);
  });

  testWidgets('a changed backend limit is used next time', (tester) async {
    final profiles = _FakeProfiles();
    profiles.config = const ProfileConfig(
        bioMaxLength: 500, displayNameMaxLength: 50, minAge: 18, maxAge: 99);
    await _openEditProfile(tester, profiles);
    expect(find.text('5 / 500'), findsOneWidget);
  });

  testWidgets('an invalid age is caught before saving', (tester) async {
    final profiles = _FakeProfiles();
    await _openEditProfile(tester, profiles);
    await tester.enterText(find.byKey(const Key('editAge')), '15');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Age must be between 18 and 99'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('editAge')), '');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Age is required'), findsOneWidget);
    expect(profiles.saved, isEmpty);
  });

  testWidgets('saving sends every field and shows the saved profile',
      (tester) async {
    final profiles = _FakeProfiles();
    final state = await _openEditProfile(tester, profiles);
    await tester.enterText(find.byKey(const Key('editDisplayName')), 'Mark');
    await tester.enterText(
        find.byKey(const Key('editBio')), 'Coffee and long walks.');
    await tester.enterText(find.byKey(const Key('editAge')), '28');
    await tester.tap(find.widgetWithText(FilterChip, LookingFor.dates.label));
    await tester.tap(find.widgetWithText(FilterChip, LookingFor.chat.label));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();

    final edit = profiles.saved.single;
    expect(edit.displayName, 'Mark');
    expect(edit.bio, 'Coffee and long walks.');
    expect(edit.age, 28);
    expect(edit.lookingFor, {LookingFor.chat}); // dates was deselected
    expect(find.byKey(const Key('saveProfile')), findsNothing); // closed
    expect(find.text('Profile saved'), findsOneWidget);
    expect(state.myName, 'Mark');
    expect(state.myAge, 28);
    expect(find.text('Mark, 28'), findsOneWidget);
    expect(find.text('Coffee and long walks.'), findsOneWidget);
  });

  testWidgets('clearing every choice saves an empty selection', (tester) async {
    final profiles = _FakeProfiles();
    final state = await _openEditProfile(tester, profiles);
    await tester.tap(find.widgetWithText(FilterChip, LookingFor.dates.label));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(profiles.saved.single.lookingFor, isEmpty);
    expect(state.myLookingFor, isEmpty);
  });

  testWidgets('server validation errors show on the field and keep the input',
      (tester) async {
    final profiles = _FakeProfiles()
      ..failSaveWith = const ProfileValidationException(
          {'bio': 'Bio can be at most 120 characters'});
    await _openEditProfile(tester, profiles);
    await tester.enterText(find.byKey(const Key('editBio')), 'Still here');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Bio can be at most 120 characters'), findsOneWidget);
    expect(_fieldText(tester, 'editBio'), 'Still here');
    expect(find.text('Profile saved'), findsNothing);
  });

  testWidgets('a failed save keeps the form and reports no success',
      (tester) async {
    final profiles = _FakeProfiles()
      ..failSaveWith = const BackendException('Could not reach the server.');
    final state = await _openEditProfile(tester, profiles);
    await tester.enterText(find.byKey(const Key('editDisplayName')), 'Mark');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(_fieldText(tester, 'editDisplayName'), 'Mark');
    expect(find.text('Profile saved'), findsNothing);
    expect(state.myName, 'Marky'); // unchanged until the database has it
  });

  testWidgets('an expired session returns to sign-in', (tester) async {
    final profiles = _FakeProfiles()
      ..failSaveWith = const SessionRejectedException();
    final state = await _openEditProfile(tester, profiles);
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('the display name limit and counter come from the backend',
      (tester) async {
    await _openEditProfile(tester, _FakeProfiles());
    expect(find.text('5 / 50'), findsOneWidget); // "Marky"
    await tester.enterText(find.byKey(const Key('editDisplayName')), 'x' * 60);
    await tester.pump();
    expect(_fieldText(tester, 'editDisplayName'), 'x' * 50);
    expect(find.text('50 / 50'), findsOneWidget);
  });
}
