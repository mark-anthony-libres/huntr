import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/agreement_service.dart';
import '../services/location_permission.dart';
import '../services/location_service.dart';
import '../services/notification_sound.dart';
import '../services/profile_service.dart';
import '../services/session_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/huntr_loader.dart';
import 'agreement_screen.dart';
import 'entry_screen.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';

/// The only way into the app. Without a verified backend session the user
/// sees sign-in and nothing else. After sign-in the saved profile decides:
/// missing age or location means onboarding, otherwise the app.
class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    this.sessions,
    this.profiles,
    this.agreements,
    this.locate = locateDevice,
    this.locationAccess,
  });

  /// Restores and saves the session across launches. Null skips both.
  final SessionService? sessions;

  /// Loads and saves the profile on the backend. Null keeps onboarding local.
  final ProfileService? profiles;

  /// The agreement new users accept before onboarding. Null skips it.
  final AgreementService? agreements;

  final LocateDevice locate;

  /// The location permission (required; the app's gate asks for it). Null:
  /// the location is read as before.
  final LocationAccess? locationAccess;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  bool _restoring = false;
  String? _signInMessage;

  /// The session token whose profile was last loaded.
  String? _profileLoadedFor;
  bool _loadingProfile = false;

  /// Profile form limits, loaded for onboarding.
  ProfileConfig? _profileConfig;
  String? _profileError;

  /// The location update waiting for the permission.
  (ProfileService, String)? _locationPending;

  void _locationChanged() {
    final pending = _locationPending;
    if (pending != null && widget.locationAccess!.granted) {
      unawaited(_refreshLocation(pending.$1, pending.$2));
    }
  }

  @override
  void dispose() {
    widget.locationAccess?.removeListener(_locationChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.locationAccess?.addListener(_locationChanged);
    final sessions = widget.sessions;
    if (sessions != null) {
      _restoring = true;
      unawaited(_restore(sessions));
    }
  }

  Future<void> _restore(SessionService sessions) async {
    String? token;
    String? error;
    try {
      token = await sessions.restoreVerifiedToken();
    } on BackendException catch (e) {
      error = '${e.message} Sign in again when it is back.';
    } catch (_) {
      error = 'Your saved session could not be checked. Please sign in.';
    }
    if (!mounted) return;
    final app = AppScope.read(context);
    if (token != null && !app.signedIn) app.startSession(token);
    setState(() {
      _restoring = false;
      _signInMessage = error;
    });
  }

  Future<void> _loadProfile(ProfileService profiles, String token) async {
    try {
      final profile = await profiles.fetchMine(token);
      if (!mounted) return;
      final app = AppScope.read(context);
      // The saved privacy settings apply everywhere, onboarded or not.
      app.updateMe(
        online: profile.privacy.showOnline,
        distance: profile.privacy.showDistance,
        onMap: profile.privacy.showOnMap,
      );
      app.myStats = profile.stats;
      app.anonymousMessaging = profile.privacy.anonymousMessaging;
      app.anonymousName = profile.anonymousName;
      app.updateNotifications(
          taps: profile.privacy.notifyTaps,
          messages: profile.privacy.notifyMessages,
          storyReplies: profile.privacy.notifyStoryReplies);
      app.notificationSound =
          NotificationSound.fromWire(profile.privacy.notificationSound);
      if (!profile.onboarded) {
        // Onboarding shows the backend's limits. Without them it still works:
        // the backend enforces them when onboarding is saved.
        try {
          _profileConfig = await profiles.fetchConfig(token);
        } catch (error) {
          debugPrint('Profile limits not loaded for onboarding: $error');
        }
      }
      if (!mounted) return;
      if (profile.onboarded) {
        _applyProfile(app, profile);
        unawaited(_refreshLocation(profiles, token));
      }
      _profileError = null;
    } on SessionRejectedException catch (e) {
      await _endSession(e.message);
    } on BackendException catch (e) {
      _profileError = e.message;
    } catch (_) {
      _profileError = 'Your profile could not be loaded.';
    }
    if (mounted) setState(() => _loadingProfile = false);
  }

  /// Each app open records where the user is now. The app works without it,
  /// so a failure (no permission, offline) is only logged. Without the
  /// permission it waits: the location gate asks, then this runs again.
  Future<void> _refreshLocation(ProfileService profiles, String token) async {
    final access = widget.locationAccess;
    if (access != null && !access.granted) {
      _locationPending = (profiles, token);
      return;
    }
    _locationPending = null;
    try {
      final location = await widget.locate();
      await profiles.updateLocation(token, location);
      if (mounted) AppScope.read(context).updateMyLocation(location);
    } catch (error) {
      debugPrint('Current location not updated: $error');
    }
  }

  void _applyProfile(AppState app, MyProfile profile) {
    app
      ..myUserId = profile.id
      ..myIsNew = profile.isNew;
    final latitude = profile.latitude;
    final longitude = profile.longitude;
    app.completeOnboarding(
      name: profile.displayName ?? '',
      age: profile.age!,
      lookingFor: LookingFor.fromNames(profile.lookingFor),
      bio: profile.bio ?? '',
      location: latitude == null || longitude == null
          ? null
          : GeoPoint(latitude: latitude, longitude: longitude),
    );
  }

  /// Saves onboarding on the backend first; the app opens only once it's stored.
  Future<void> _finishOnboarding(OnboardingAnswers answers) async {
    final app = AppScope.read(context);
    final profiles = widget.profiles;
    if (profiles == null) {
      app.completeOnboarding(
        name: answers.displayName,
        age: answers.age,
        lookingFor: answers.lookingFor,
        location: answers.location,
      );
      return;
    }
    try {
      final saved = await profiles.saveOnboarding(app.sessionToken!, answers);
      if (mounted) _applyProfile(app, saved);
    } on SessionRejectedException catch (e) {
      await _endSession(e.message);
    }
  }

  Future<void> _endSession(String message) async {
    await widget.sessions?.forget();
    if (!mounted) return;
    setState(() => _signInMessage = message);
    AppScope.read(context).endSession();
  }

  /// Declining deactivates the account on the backend, then signs out.
  /// Other failures are thrown so the agreement screen can show them.
  Future<void> _declineAgreement(
      AgreementService agreements, String token) async {
    try {
      await agreements.decline(token);
    } on SessionRejectedException {
      // Already signed out on the backend; nothing left to deactivate here.
    }
    await _endSession(
        'Your account was deactivated because you declined the terms.');
  }

  void _retryProfile() => setState(() {
        _profileLoadedFor = null;
        _profileError = null;
      });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final profiles = widget.profiles;
    final token = app.sessionToken;
    if (token != null &&
        !app.onboarded &&
        profiles != null &&
        _profileLoadedFor != token) {
      _profileLoadedFor = token;
      _loadingProfile = true;
      unawaited(_loadProfile(profiles, token));
    }

    final Widget screen;
    if (_restoring || _loadingProfile) {
      screen = const _CheckingSession(key: ValueKey('checking'));
    } else if (!app.signedIn) {
      // signed out from a page on top (Settings, a chat, ...): close them,
      // so sign-in isn't left hidden underneath
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      screen = EntryScreen(
        key: const ValueKey('signIn'),
        sessions: widget.sessions,
        initialError: _signInMessage,
      );
    } else if (_profileError != null) {
      screen = _ProfileLoadFailed(
        key: const ValueKey('profileError'),
        message: _profileError!,
        onRetry: _retryProfile,
      );
    } else if (!app.onboarded &&
        !app.agreementAccepted &&
        widget.agreements != null) {
      screen = AgreementScreen(
        key: const ValueKey('agreement'),
        agreements: widget.agreements!,
        onAccept: app.acceptAgreement,
        onDecline: () => _declineAgreement(widget.agreements!, token!),
      );
    } else if (!app.onboarded) {
      screen = OnboardingScreen(
        key: const ValueKey('onboarding'),
        locate: widget.locate,
        displayNameMaxLength: _profileConfig?.displayNameMaxLength,
        onFinished: _finishOnboarding,
      );
    } else {
      screen = const HomeShell(key: ValueKey('home'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: screen,
    );
  }
}

class _CheckingSession extends StatelessWidget {
  const _CheckingSession({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: HuntrColors.night,
      // the same animation as the web page before the app starts
      body: Center(child: HuntrLoader()),
    );
  }
}

class _ProfileLoadFailed extends StatelessWidget {
  const _ProfileLoadFailed(
      {super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuntrColors.night,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
