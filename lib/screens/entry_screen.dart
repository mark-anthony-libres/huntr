import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_oauth_config.dart';
import '../services/huntr_backend.dart';
import '../services/photo_cache/photo_cache.dart';
import '../services/services_scope.dart';
import '../services/session_service.dart';
import '../state/app_state.dart';
import 'sign_in_screen.dart';
import '../widgets/google_sign_in_web_button_stub.dart'
    if (dart.library.js_interop) '../widgets/google_sign_in_web_button_web.dart'
    as web_button;

/// Sign-in. A session only starts once the Huntr backend has verified the
/// Google account and issued a session token.
class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, this.sessions, this.initialError});

  /// Saves the session token for the next launch. Null keeps it in memory only.
  final SessionService? sessions;

  /// Shown until the user tries again, e.g. why a saved session was not restored.
  final String? initialError;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

/// google_sign_in may only be initialized once per app run, but this screen
/// is rebuilt after every sign-out (declined terms, deleted account, expired
/// session). Every instance shares one setup; a failed one may be retried.
Future<void>? _googleSignInSetup;

Future<void> _initializeGoogleSignInOnce(GoogleOAuthConfig config) =>
    _googleSignInSetup ??= GoogleSignIn.instance
        .initialize(
      clientId: config.clientId,
      serverClientId: config.serverClientId,
    )
        .catchError((Object error, StackTrace stackTrace) {
      _googleSignInSetup = null;
      Error.throwWithStackTrace(error, stackTrace);
    });

/// Signs out of Google on this device (after logging out of Huntr), so the
/// next sign-in can pick an account. Nothing to do if Google was never set up
/// in this run.
Future<void> signOutOfGoogle() async {
  final setup = _googleSignInSetup;
  if (setup == null) return;
  try {
    await setup;
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    // already signed out, or Google unavailable: Huntr is logged out anyway
  }
}

class _EntryScreenState extends State<EntryScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSubscription;
  String _backendUrl = '';
  bool _googleInitialized = false;
  bool _googleSigningIn = false;
  late String? _googleError = widget.initialError;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeGoogleSignIn());
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      final config = await GoogleOAuthConfig.load();
      final missing = !config.isConfigured
          ? 'the Google client IDs'
          : config.backendUrl.trim().isEmpty
              ? 'the Huntr backend URL'
              : null;
      if (missing != null) {
        if (!mounted) return;
        setState(() {
          _googleInitialized = false;
          _googleError = 'Google sign-in is not configured. Add $missing to '
              'assets/google_oauth.json.';
        });
        return;
      }
      _backendUrl = config.backendUrl.trim();
      await _initializeGoogleSignInOnce(config);
      if (!mounted) return;
      _authSubscription = _googleSignIn.authenticationEvents.listen(
        _handleAuthenticationEvent,
        onError: (Object error) => _handleGoogleSignInError(error),
      );
      setState(() => _googleInitialized = true);
    } catch (error) {
      _handleGoogleSignInError(error);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!_googleInitialized) {
      await _initializeGoogleSignIn();
    }
    if (!_googleInitialized || !_googleSignIn.supportsAuthenticate()) return;

    setState(() {
      _googleSigningIn = true;
      _googleError = null;
    });
    try {
      final account = await _googleSignIn.authenticate();
      await _startBackendSession(account);
    } catch (error) {
      _handleGoogleSignInError(error);
    }
  }

  void _handleAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      unawaited(_startBackendSession(event.user)
          .catchError((Object error) => _handleGoogleSignInError(error)));
    }
  }

  /// The backend sign-in in progress. On Android one Google sign-in arrives
  /// twice (authenticate() returns it and authenticationEvents reports it),
  /// so the second call joins the first instead of logging in again.
  Future<void>? _backendSignIn;

  Future<void> _startBackendSession(GoogleSignInAccount account) =>
      _backendSignIn ??= _exchangeForSession(account)
          .whenComplete(() => _backendSignIn = null);

  /// Exchanges the Google account for a Huntr session token. Signing in with
  /// Google alone is not enough to enter the app.
  Future<void> _exchangeForSession(GoogleSignInAccount account) async {
    if (!mounted) return;
    final app = AppScope.read(context);
    final caches = [
      for (final collection in PhotoCollection.values)
        ServicesScope.photoCacheOf(context, collection)
    ];
    if (app.signedIn) return;
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const BackendException('Google did not return an ID token.');
    }
    final backendAccount = await signInToBackendWithGoogle(
        backendUrl: _backendUrl, idToken: idToken);
    await widget.sessions?.remember(backendAccount.token);
    // This may be a different account: none of the last one's photos.
    await Future.wait([
      for (final cache in caches)
        if (cache != null) cache.clear()
    ]);
    if (!mounted) return;
    app.startSession(backendAccount.token);
  }

  void _handleGoogleSignInError(Object error) {
    // The message shown is generic; keep the real cause in the logs.
    debugPrint('Google sign-in error: $error');
    if (!mounted) return;
    final wasCancelled = error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled;
    setState(() {
      _googleSigningIn = false;
      _googleError = wasCancelled
          ? null
          : error is BackendException
              ? error.message
              : 'Google sign-in failed. Check your Google OAuth setup and try again.'
                  // Debug builds only: the real cause, to diagnose setup issues.
                  '${kDebugMode ? '\n[debug] $error' : ''}';
    });
  }

  void _showFacebookUnavailable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Facebook sign-in is not available yet. '
            'Please sign in with Google.'),
      ));
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SignInScreen(
      onGoogleSignIn: _signInWithGoogle,
      onFacebookSignIn: _showFacebookUnavailable,
      googleSignInReady: _googleInitialized,
      googleSignInBusy: _googleSigningIn,
      googleSignInError: _googleError,
      webGoogleSignInButtonBuilder: kIsWeb && _googleInitialized
          ? web_button.buildGoogleSignInButton
          : null,
    );
  }
}
