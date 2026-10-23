import 'package:flutter/material.dart';
import '../../theme.dart';

class SignInButton extends StatefulWidget {
  const SignInButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.dense = false,
    this.highlighted = false,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;

  /// Shorter button for small screens.
  final bool dense;

  /// Forces the hover look. Used when the pointer is over something that
  /// hides this button from Flutter (Google's web button).
  final bool highlighted;

  @override
  State<SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<SignInButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    final active = widget.onPressed != null && (_hovered || widget.highlighted);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: active ? 1.02 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, glow, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: HuntrColors.orange.withValues(alpha: 0.28 * glow),
                  blurRadius: 22 * glow,
                  spreadRadius: glow,
                ),
              ],
            ),
            child: _button(glow, compact),
          ),
        ),
      ),
    );
  }

  Widget _button(double glow, bool compact) {
    return OutlinedButton(
      onPressed: widget.onPressed,
      style: OutlinedButton.styleFrom(
        // white hover/press tint suits the dark card; the glow above is the
        // main hover effect
        overlayColor: Colors.white,
        minimumSize: Size.fromHeight(widget.dense ? 58 : (compact ? 62 : 88)),
        backgroundColor:
            Color.lerp(HuntrColors.surface, HuntrColors.surfaceHigh, glow),
        foregroundColor: Colors.white,
        side: BorderSide(
          color: Color.lerp(const Color(0xFF353944), HuntrColors.orange, glow)!,
          width: 1.4,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
        textStyle: TextStyle(
          fontFamily: huntrFontFamily,
          fontSize: widget.dense || compact ? 17 : 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 32 : 48,
            height: compact ? 36 : 48,
            child: Center(child: widget.icon),
          ),
          Container(
            width: 1,
            height: widget.dense || compact ? 30 : 48,
            margin: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
            color: const Color(0xFF353944),
          ),
          Expanded(child: Text(widget.label, textAlign: TextAlign.center)),
          Icon(
            Icons.chevron_right,
            color: HuntrColors.muted,
            size: compact ? 22 : 30,
          ),
        ],
      ),
    );
  }
}
