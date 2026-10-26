import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/agreement_service.dart';
import '../services/services_scope.dart';
import '../theme.dart';
import 'agreement_screen.dart';
import '../widgets/sign_in/google_sign_in_card.dart';
import '../widgets/sign_in/sign_in_button.dart';
import '../widgets/sign_in/privacy_card.dart';
import '../widgets/install_banner.dart' show showGetTheAppSheet;
import '../widgets/sign_in/brand_marks.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({
    super.key,
    required this.onGoogleSignIn,
    required this.onFacebookSignIn,
    required this.googleSignInReady,
    required this.googleSignInBusy,
    required this.googleSignInError,
    this.webGoogleSignInButtonBuilder,
  });

  final VoidCallback onGoogleSignIn;
  final VoidCallback onFacebookSignIn;
  final bool googleSignInReady;
  final bool googleSignInBusy;
  final String? googleSignInError;
  final WebGoogleButtonBuilder? webGoogleSignInButtonBuilder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Everything must fit on one screen without scrolling, so shrink the
    // spacing and type on short screens instead.
    final dense = size.height < 800;
    final narrow = size.width < 480;
    // phones: sized so the title and text fit their lines at full size
    // (nothing gets shrunk to fit), with room to breathe
    final titleSize = narrow ? 30.0 : (dense ? 32.0 : 42.0);
    final bodySize = narrow ? 16.0 : (dense ? 17.0 : 22.0);
    final gap = dense ? 14.0 : (narrow ? 20.0 : 22.0);

    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.25),
              radius: 1.15,
              colors: [Color(0xFF17130F), HuntrColors.night],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final contentWidth =
                  (box.maxWidth - (narrow ? 40 : 48)).clamp(0.0, 520.0);
              final logoHeight = (box.maxHeight * (narrow ? 0.12 : 0.15))
                  .clamp(60.0, narrow ? 112.0 : 140.0);
              // scaleDown guarantees the screen never overflows or scrolls:
              // if the content is ever taller than the screen it shrinks.
              return Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: dense ? 12 : 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: contentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: logoHeight,
                            child: Image.asset(
                              'assets/huntr_logo.png',
                              fit: BoxFit.contain,
                              semanticLabel: 'Huntr logo',
                            ),
                          ),
                          SizedBox(height: gap * 1.3),
                          Text(
                            'Find your\nkind of connection.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w800,
                              height: 1.12,
                              letterSpacing: -0.6,
                            ),
                          ),
                          SizedBox(height: gap * 0.8),
                          Text(
                            'Meet people nearby, make a connection,\nand see where it goes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: HuntrColors.muted,
                              fontSize: bodySize,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: gap * 2),
                          GoogleSignInCard(
                            dense: dense,
                            busy: googleSignInBusy,
                            onPressed: googleSignInReady && !googleSignInBusy
                                ? onGoogleSignIn
                                : null,
                            webButtonBuilder: webGoogleSignInButtonBuilder,
                          ),
                          SizedBox(height: dense || narrow ? 12 : 18),
                          SignInButton(
                            key: const Key('signInFacebook'),
                            dense: dense,
                            onPressed: onFacebookSignIn,
                            icon: const FacebookMark(),
                            label: 'Sign in with Facebook',
                          ),
                          SizedBox(height: gap * 1.4),
                          if (size.height >= 560) ...[
                            PrivacyCard(bodySize: bodySize, dense: dense),
                            SizedBox(height: gap),
                          ],
                          if (googleSignInError != null) ...[
                            Text(
                              googleSignInError!,
                              key: const Key('googleSignInError'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFF9B8A),
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: gap * 0.6),
                          ],
                          _LegalLinks(
                            agreements: ServicesScope.agreementsOf(context) ??
                                const AgreementService(),
                            fontSize: dense || narrow ? 13 : 15,
                          ),
                          // the website: the Android app, until it's on
                          // Google Play
                          if (kIsWeb) ...[
                            SizedBox(height: gap * 0.6),
                            Center(
                              child: TextButton.icon(
                                key: const Key('signInGetTheApp'),
                                onPressed: () => showGetTheAppSheet(context),
                                icon: const Icon(Icons.android_rounded,
                                    size: 20),
                                label: Text('Get the Android app',
                                    style: TextStyle(
                                        fontSize: dense || narrow ? 14 : 16,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "By continuing, you agree to …" with the terms, guidelines and privacy
/// policy to read before signing in.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks({required this.agreements, required this.fontSize});

  final AgreementService agreements;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text =
        TextStyle(color: HuntrColors.muted, fontSize: fontSize, height: 1.4);
    Widget link(String key, String label, AgreementScreen screen) => InkWell(
          key: Key(key),
          borderRadius: BorderRadius.circular(4),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => screen)),
          child: Text(label,
              style: text.copyWith(
                color: HuntrColors.orange,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: HuntrColors.orange,
              )),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text("By continuing, you agree to HUNTR's ", style: text),
        link('signInTerms', 'Terms', AgreementScreen(agreements: agreements)),
        Text(', ', style: text),
        link('signInGuidelines', 'Community Guidelines',
            AgreementScreen.communityGuidelines(agreements: agreements)),
        Text(' and ', style: text),
        link('signInPrivacy', 'Privacy Policy',
            AgreementScreen.privacyPolicy(agreements: agreements)),
        Text('.', style: text),
      ],
    );
  }
}
