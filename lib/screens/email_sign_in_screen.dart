import 'dart:async';
import 'dart:math' as math;

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/turnstile_config.dart';

import '../services/huntr_backend.dart';
import '../theme.dart';
import '../widgets/sign_in/brand_marks.dart';
import 'sign_in_screen.dart' show signInBackground;

/// Signing in or signing up with an email address instead of Google: a
/// 6-digit code is emailed, and entering it signs in, or creates the account
/// the first time. No password. Pops with the [BackendAccount] once signed
/// in (EntryScreen starts the session).
///
/// The code works for a short time (counted down); asking again for the same
/// address meanwhile reuses it. A code to a different address waits for the
/// network's cooldown (counted down too). Each code request first passes a
/// bot check (Cloudflare Turnstile), shown above its button.
class EmailSignInScreen extends StatefulWidget {
  const EmailSignInScreen({
    super.key,
    required this.requestCode,
    required this.signIn,
    this.botCheckSiteKey,
    this.onUseGoogle,
  });

  /// Sign in with Google instead, offered when email sign-in won't work for
  /// now ([EmailSignInUseGoogleException]). Null: not offered.
  final VoidCallback? onUseGoogle;

  /// Emails a code to the address, or reuses the one still working
  /// ([requestEmailSignInCode]), with the bot check's token.
  final Future<EmailSignInCode> Function(String email, String? turnstileToken)
      requestCode;

  /// The Turnstile widget's site key ([TurnstileConfig.siteKey]). Null: no
  /// bot check (tests).
  final String? botCheckSiteKey;

  /// Signs in with the address and its code ([signInToBackendWithEmailCode]).
  final Future<BackendAccount> Function(String email, String code) signIn;

  @override
  State<EmailSignInScreen> createState() => _EmailSignInScreenState();
}

/// Shown instead of [EmailSignInScreen] while no codes can be emailed (the
/// email provider's daily or monthly allowance is used up): the logo, a
/// crossed-out envelope, "Sorry..." and Sign in with Google. Pops true when
/// Sign in with Google is chosen.
class EmailSignInUnavailableScreen extends StatelessWidget {
  const EmailSignInUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: DecoratedBox(
        decoration: signInBackground,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 64,
                      child: Image.asset('assets/huntr_logo.png',
                          fit: BoxFit.contain, semanticLabel: 'Huntr logo'),
                    ),
                    const SizedBox(height: 36),
                    const Center(child: _EmailUnavailableMark()),
                    const SizedBox(height: 28),
                    const Text(
                      'Sorry...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Email sign-in is temporarily unavailable.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'You can use Sign in with Google\nin the meantime.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: HuntrColors.muted, fontSize: 16, height: 1.45),
                    ),
                    const SizedBox(height: 32),
                    _GoogleButton(
                      key: const Key('emailUnavailableGoogle'),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round envelope with a "no" badge and short lines around it.
class _EmailUnavailableMark extends StatelessWidget {
  const _EmailUnavailableMark();

  @override
  Widget build(BuildContext context) {
    final accent = HuntrColors.orange;
    // a short line at (x, y) in the 180x140 box, turned by [turns]
    Widget spark(double x, double y, double turns) => Positioned(
          left: x,
          top: y,
          child: Transform.rotate(
            angle: turns * 2 * 3.141592653589793,
            child: Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
    return SizedBox(
      width: 180,
      height: 140,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          spark(8, 30, 0.07),
          spark(22, 8, 0.17),
          spark(140, 8, -0.17),
          spark(154, 30, -0.07),
          Positioned(
            left: 30,
            top: 10,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [HuntrColors.surfaceHigh, HuntrColors.surface],
                ),
                boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.18), blurRadius: 40),
                ],
              ),
              child: const Icon(Icons.mail_outline_rounded,
                  size: 60, color: Color(0xFFE6E1EA)),
            ),
          ),
          Positioned(
            left: 104,
            top: 76,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HuntrColors.coral,
                border: Border.all(color: HuntrColors.surface, width: 3),
              ),
              child: const Icon(Icons.block_rounded,
                  size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// "0:42"
String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class _EmailSignInScreenState extends State<EmailSignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  /// The address the code went to (null: no code asked for yet).
  String? _sentTo;

  /// The code sent earlier was reused (no new email).
  bool _reused = false;

  /// Email sign-in was refused with Google suggested: its button takes the
  /// main button's place (until another address is typed).
  bool _suggestGoogle = false;

  /// The bot check's token for the next code request (each works once).
  final _botCheck = TurnstileController();
  String? _turnstileToken;
  bool get _botCheckPassed =>
      widget.botCheckSiteKey == null || _turnstileToken != null;
  bool _busy = false;
  String? _error;

  /// Seconds until the code stops working, and until a code to a different
  /// address may be sent; a ticker counts both down every second.
  int _codeSecondsLeft = 0;
  int _cooldownSecondsLeft = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _botCheck.dispose();
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Counts down until both the code and the cooldown are over.
  void _keepCountingDown() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {
        if (_codeSecondsLeft > 0) _codeSecondsLeft--;
        if (_cooldownSecondsLeft > 0) {
          _cooldownSecondsLeft--;
          // the wait is over: its message goes with it
          if (_cooldownSecondsLeft == 0) _error = null;
        }
      });
      if (_codeSecondsLeft == 0 && _cooldownSecondsLeft == 0) timer.cancel();
    });
  }

  Future<void> _sendCode(String rawEmail) async {
    final email = rawEmail.trim().toLowerCase();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final turnstileToken = _turnstileToken;
    setState(() {
      _busy = true;
      _error = null;
      // used up by this request: the check gives a new one
      _turnstileToken = null;
    });
    _refreshBotCheck();
    try {
      final code = await widget.requestCode(email, turnstileToken);
      if (!mounted) return;
      setState(() {
        _sentTo = email;
        _reused = code.reused;
        _codeSecondsLeft = code.expiresIn.inSeconds;
        _cooldownSecondsLeft = 0;
        _code.clear();
      });
      _keepCountingDown();
      _codeFocus.requestFocus();
    } on EmailSignInUseGoogleException catch (error) {
      _offerGoogle(error);
    } on EmailCodeCooldownException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _cooldownSecondsLeft = error.retryIn.inSeconds;
      });
      _keepCountingDown();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    final email = _sentTo;
    final code = _code.text.trim();
    if (email == null || code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await widget.signIn(email, code);
      if (!mounted) return;
      Navigator.of(context).pop(account);
    } on EmailSignInUseGoogleException catch (error) {
      _offerGoogle(error);
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refreshBotCheck() {
    if (widget.botCheckSiteKey == null || !_botCheck.isWidgetReady) return;
    _botCheck.refreshToken().catchError(
        (Object error) => debugPrint('Bot check not refreshed: $error'));
  }

  /// Cloudflare's check: usually passes by itself, sometimes asks to tick a
  /// box. Its token unlocks the button below it.
  Widget _botCheckBox() {
    final siteKey = widget.botCheckSiteKey;
    if (siteKey == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: CloudflareTurnstile(
          siteKey: siteKey,
          baseUrl: TurnstileConfig.baseUrl,
          controller: _botCheck,
          options: TurnstileOptions(
            theme: TurnstileTheme.dark,
            refreshExpired: TurnstileRefreshExpired.auto,
            borderRadius: BorderRadius.circular(12),
          ),
          onTokenReceived: (token) {
            if (mounted) setState(() => _turnstileToken = token);
          },
          onTokenExpired: () {
            if (mounted) setState(() => _turnstileToken = null);
          },
          onError: (error) {
            debugPrint('Bot check error: ${error.message}');
            if (mounted) {
              setState(() {
                _turnstileToken = null;
                _error = "The check didn't load. Check your connection and "
                    'try again.';
              });
            }
          },
        ),
      ),
    );
  }

  void _offerGoogle(EmailSignInUseGoogleException error) {
    if (!mounted) return;
    setState(() {
      _error = error.message;
      _suggestGoogle = widget.onUseGoogle != null;
    });
  }

  /// Another address typed: it may work, so the usual button is back.
  void _addressChanged(String _) {
    if (!_suggestGoogle) return;
    setState(() {
      _suggestGoogle = false;
      _error = null;
    });
  }

  void _showError(Object error) {
    debugPrint('Email sign-in error: $error');
    if (!mounted) return;
    setState(() => _error = error is BackendException
        ? error.message
        : "Couldn't reach HUNTR. Check your connection and try again.");
  }

  void _useAnotherEmail() {
    setState(() {
      _sentTo = null;
      _codeSecondsLeft = 0;
      _error = null;
      _suggestGoogle = false;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Image.asset('assets/huntr_logo.png',
            height: 40, semanticLabel: 'Huntr logo'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _WavePainter())),
          // sized to fit on one screen: the envelope shrinks on shorter
          // screens (and more when the keyboard leaves little room); only
          // if it still doesn't fit (a very small screen) does it scroll,
          // at full size rather than shrunk
          SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              final height = box.maxHeight;
              final compact = height < 820;
              final envelope = height >= 820
                  ? 1.0
                  : height >= 640
                      ? 0.7
                      : 0.5;
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  // short content sits in the middle of the screen
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: SizedBox(
                              width: 200 * envelope,
                              height: 170 * envelope,
                              child: const FittedBox(child: _EnvelopeTile()),
                            ),
                          ),
                          SizedBox(height: compact ? 14 : 26),
                          Text(
                            sentTo == null
                                ? 'Continue with Email'
                                : 'Verify your email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: compact ? 26 : 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4),
                          ),
                          SizedBox(height: compact ? 10 : 14),
                          ...(sentTo == null
                              ? _emailStep(compact)
                              : _codeStep(sentTo, compact)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  List<Widget> _emailStep(bool compact) {
    final waiting = _cooldownSecondsLeft > 0;
    return [
      Text(
        'Enter your email and we’ll send you a 6-digit code to sign in, or '
        'to create your account if you’re new. No password needed.',
        textAlign: TextAlign.center,
        style: TextStyle(
            color: HuntrColors.muted,
            fontSize: compact ? 15 : 16,
            height: compact ? 1.35 : 1.45),
      ),
      SizedBox(height: compact ? 18 : 30),
      _EmailField(
        controller: _email,
        enabled: !_busy,
        onChanged: _addressChanged,
        onSubmitted: (value) => _sendCode(value),
      ),
      if (!_suggestGoogle) _botCheckBox(),
      ..._errorText(),
      SizedBox(height: compact ? 14 : 22),
      _suggestGoogle
          ? _GoogleButton(
              key: const Key('emailSignInUseGoogle'),
              onPressed: widget.onUseGoogle!)
          : _GlowButton(
              key: const Key('emailSignInSend'),
              label: waiting
                  ? 'Try again in ${_cooldownSecondsLeft}s'
                  : 'Send code',
              trailingArrow: !waiting,
              busy: _busy,
              onPressed: waiting || !_botCheckPassed
                  ? null
                  : () => _sendCode(_email.text),
            ),
    ];
  }

  List<Widget> _codeStep(String sentTo, bool compact) {
    final expired = _codeSecondsLeft == 0;
    return [
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text: _reused
                  ? 'The code we sent earlier to\n'
                  : 'We sent a 6-digit code to\n'),
          TextSpan(
              text: sentTo,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          TextSpan(
              text: _reused
                  ? ' still works.\nCheck your spam folder if you don’t see it.'
                  : '.\nCheck your spam folder if you don’t see it.'),
        ]),
        textAlign: TextAlign.center,
        style: TextStyle(
            color: HuntrColors.muted,
            fontSize: compact ? 15 : 16,
            height: compact ? 1.35 : 1.45),
      ),
      SizedBox(height: compact ? 18 : 30),
      _CodeBoxes(
        controller: _code,
        focusNode: _codeFocus,
        enabled: !_busy && !expired,
        onChanged: (value) {
          setState(() {});
          if (value.length == 6 && !_busy) _signIn();
        },
        onSubmitted: (_) => _signIn(),
      ),
      SizedBox(height: compact ? 14 : 22),
      expired
          ? const Text('This code has expired. Send a new one.',
              key: Key('emailSignInExpiry'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFFF9B8A), fontSize: 15))
          : Text.rich(
              TextSpan(children: [
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.schedule_rounded,
                        size: 22, color: HuntrColors.muted),
                  ),
                ),
                const TextSpan(text: 'Code expires in '),
                TextSpan(
                    text: _clock(_codeSecondsLeft),
                    style: TextStyle(
                        color: HuntrColors.orange,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ]),
              key: const Key('emailSignInExpiry'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: HuntrColors.muted, fontSize: 16),
            ),
      if (expired) _botCheckBox(),
      ..._errorText(),
      SizedBox(height: compact ? 14 : 24),
      _suggestGoogle
          ? _GoogleButton(
              key: const Key('emailSignInUseGoogle'),
              onPressed: widget.onUseGoogle!)
          : expired
              ? _GlowButton(
                  key: const Key('emailSignInResend'),
                  label: _cooldownSecondsLeft > 0
                      ? 'Try again in ${_cooldownSecondsLeft}s'
                      : 'Send a new code',
                  busy: _busy,
                  onPressed: _cooldownSecondsLeft > 0 || !_botCheckPassed
                      ? null
                      : () => _sendCode(sentTo),
                )
              : _GlowButton(
                  key: const Key('emailSignInSubmit'),
                  label: 'Sign in',
                  busy: _busy,
                  onPressed: _code.text.length == 6 ? _signIn : null,
                ),
      SizedBox(height: compact ? 6 : 18),
      Center(
        child: TextButton(
          key: const Key('emailSignInOtherAddress'),
          onPressed: _busy ? null : _useAnotherEmail,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('Use another email',
              style: TextStyle(
                  fontSize: 16,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white)),
        ),
      ),
    ];
  }

  List<Widget> _errorText() => [
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            key: const Key('emailSignInError'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF9B8A), fontSize: 14),
          ),
        ],
      ];
}

/// A glowing rounded tile with an open envelope holding a hidden code, and
/// short lines at its corner.
class _EnvelopeTile extends StatelessWidget {
  const _EnvelopeTile();

  @override
  Widget build(BuildContext context) {
    final accent = HuntrColors.orange;
    Widget spark(double left, double top, double turns) => Positioned(
          left: left,
          top: top,
          child: Transform.rotate(
            angle: turns * 2 * math.pi,
            child: Container(
              width: 20,
              height: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
    return SizedBox(
      width: 200,
      height: 170,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 25,
            top: 10,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(46),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2A1A12), Color(0xFF15100D)],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.22), blurRadius: 44),
                ],
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(112, 92),
                  painter:
                      _EnvelopePainter(HuntrColors.orange, HuntrColors.ember),
                ),
              ),
            ),
          ),
          spark(160, 6, -0.2),
          spark(166, 22, -0.1),
          spark(168, 40, 0.0),
        ],
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  const _EnvelopePainter(this.accent, this.ember);

  final Color accent;
  final Color ember;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = h * 0.34;
    final body = RRect.fromLTRBR(0, top, w, h, const Radius.circular(10));
    canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(accent, Colors.black, 0.15)!, ember],
          ).createShader(body.outerRect));

    // the letter, peeking out, with the hidden code
    final letter = RRect.fromLTRBR(
        w * 0.14, 0, w * 0.86, h * 0.72, const Radius.circular(8));
    canvas.drawRRect(letter, Paint()..color = const Color(0xFFF7F2EE));
    final stars = TextPainter(
      text: const TextSpan(
          text: '*****',
          style: TextStyle(
              fontFamily: huntrFontFamily,
              color: Color(0xFF2B1A12),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2)),
      textDirection: TextDirection.ltr,
    )..layout();
    stars.paint(canvas, Offset((w - stars.width) / 2, h * 0.12));

    // the front pocket over the letter, with its fold
    final pocket = Path()
      ..moveTo(0, top + 6)
      ..lineTo(w / 2, h * 0.72)
      ..lineTo(w, top + 6)
      ..lineTo(w, h - 10)
      ..quadraticBezierTo(w, h, w - 10, h)
      ..lineTo(10, h)
      ..quadraticBezierTo(0, h, 0, h - 10)
      ..close();
    canvas.drawPath(
        pocket,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(accent, Colors.white, 0.18)!, accent],
          ).createShader(Offset.zero & size));
    final fold = Path()
      ..moveTo(0, h)
      ..lineTo(w / 2, h * 0.6)
      ..lineTo(w, h);
    canvas.drawPath(
        fold,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ember.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_EnvelopePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.ember != ember;
}

/// The glowing waves at the bottom of the screen.
class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final accent = HuntrColors.orange;
    final back = Path()
      ..moveTo(0, h * 0.88)
      ..cubicTo(w * 0.35, h * 0.80, w * 0.6, h * 0.95, w, h * 0.80)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
        back,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              accent.withValues(alpha: 0.55),
              accent.withValues(alpha: 0.05),
            ],
          ).createShader(Rect.fromLTWH(0, h * 0.78, w, h * 0.22)));
    final front = Path()
      ..moveTo(0, h * 0.95)
      ..cubicTo(w * 0.3, h * 0.92, w * 0.55, h * 1.0, w, h * 0.9)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFF0E0B0A));
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => false;
}

/// The email box: an envelope, a divider, and the address, in the accent's
/// outline.
class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final accent = HuntrColors.orange;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF121014),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: accent, width: 1.6),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 18),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.mail_outline_rounded, size: 28),
          Container(
            width: 1.4,
            height: 30,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: HuntrColors.muted.withValues(alpha: 0.6),
          ),
          Expanded(
            child: TextField(
              key: const Key('emailSignInAddress'),
              controller: controller,
              enabled: enabled,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              textInputAction: TextInputAction.send,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: const TextStyle(fontSize: 17),
              decoration: const InputDecoration(
                hintText: 'you@example.com',
                hintStyle: TextStyle(color: HuntrColors.muted, fontSize: 17),
                filled: false,
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six boxes for the code. One hidden field takes the typing (and the
/// phone's code autofill); the boxes show its digits, the next box glowing.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  static const length = 6;

  @override
  Widget build(BuildContext context) {
    final accent = HuntrColors.orange;
    final digits = controller.text;
    Widget box(int i) {
      final next = enabled && i == digits.length;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: next ? const Color(0xFF1A1210) : const Color(0xFF1B1B20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: next ? accent : const Color(0xFF34353D),
            width: next ? 1.8 : 1.2,
          ),
          boxShadow: next
              ? [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.3), blurRadius: 14)
                ]
              : null,
        ),
        child: Center(
          child: i < digits.length
              ? Text(digits[i],
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700))
              : next
                  ? Container(width: 2, height: 26, color: Colors.white)
                  : null,
        ),
      );
    }

    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: AspectRatio(aspectRatio: 0.92, child: box(i))),
            ],
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              key: const Key('emailSignInCode'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              showCursor: false,
              // hold (or right-click, or Ctrl/Cmd+V) to paste a code
              enableInteractiveSelection: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: const [_CodeFormatter(length)],
              textInputAction: TextInputAction.done,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                  border: InputBorder.none, filled: false),
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps the code to its digits, at most [length]. A paste (more than one
/// character at once, such as "Your HUNTR code: 482913" or "482 913") is the
/// whole code: its digits replace what was typed, rather than being added to
/// it.
class _CodeFormatter extends TextInputFormatter {
  const _CodeFormatter(this.length);

  final int length;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String digits(String text) => text.replaceAll(RegExp(r'\D'), '');
    final pasted = newValue.text.length - oldValue.text.length > 1;
    var code = digits(pasted && newValue.text.startsWith(oldValue.text)
        ? newValue.text.substring(oldValue.text.length)
        : newValue.text);
    if (pasted && code.isEmpty) code = digits(oldValue.text);
    if (code.length > length) code = code.substring(0, length);
    return TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }
}

/// Google's white pill: its G and "Sign in with Google".
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          minimumSize: const Size.fromHeight(58),
          shape: const StadiumBorder(),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(dimension: 22, child: GoogleMark()),
            SizedBox(width: 12),
            Flexible(
              child: Text('Sign in with Google',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

/// The big pill button: the accent fading to ember, glowing; an arrow at its
/// end when it leads on. Dimmed while it can't be pressed.
class _GlowButton extends StatelessWidget {
  const _GlowButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.busy,
    this.trailingArrow = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final accent = HuntrColors.orange;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: LinearGradient(
            colors: [
              accent,
              Color.lerp(HuntrColors.ember, Colors.black, 0.25)!
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.8)),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.35), blurRadius: 24)
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 62,
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      ),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 56),
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: enabled
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.75),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (trailingArrow)
                          const Positioned(
                            right: 24,
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 28, color: Colors.white),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
