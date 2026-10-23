import 'package:flutter/material.dart';

import 'brand_marks.dart';
import 'sign_in_button.dart';

/// Builds Google's own button on web, told when the pointer is over it.
typedef WebGoogleButtonBuilder = Widget Function(
    {required ValueChanged<bool> onHoverChanged});

/// The "Sign in with Google" card, styled like the other sign-in buttons.
class GoogleSignInCard extends StatefulWidget {
  const GoogleSignInCard({
    super.key,
    required this.onPressed,
    required this.busy,
    required this.dense,
    this.webButtonBuilder,
  });

  /// Null disables the card.
  final VoidCallback? onPressed;
  final bool busy;
  final bool dense;

  /// On web, Google only starts sign-in from its own rendered button, which
  /// sits invisibly over this card.
  final WebGoogleButtonBuilder? webButtonBuilder;

  @override
  State<GoogleSignInCard> createState() => _GoogleSignInCardState();
}

class _GoogleSignInCardState extends State<GoogleSignInCard> {
  /// Hover over Google's web button, which Flutter cannot see by itself.
  bool _webButtonHovered = false;

  void _setWebButtonHovered(bool hovered) {
    if (mounted && hovered != _webButtonHovered) {
      setState(() => _webButtonHovered = hovered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webButtonBuilder = widget.webButtonBuilder;
    return Stack(
      children: [
        SignInButton(
          key: const Key('signInGoogle'),
          dense: widget.dense,
          highlighted: _webButtonHovered,
          onPressed: webButtonBuilder != null
              ? () {} // clicks reach Google's button above
              : widget.onPressed,
          icon: widget.busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const GoogleMark(),
          label: widget.busy ? 'Signing in...' : 'Sign in with Google',
        ),
        if (webButtonBuilder != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.004,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: 400,
                  height: 40,
                  child: webButtonBuilder(onHoverChanged: _setWebButtonHovered),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
