import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart';
import 'package:web/web.dart' as web;

/// Google's rendered button. It lives in an iframe that swallows mouse events,
/// so hover is reported by watching the browser's mouse position instead.
Widget buildGoogleSignInButton({required ValueChanged<bool> onHoverChanged}) =>
    _HoverReportingButton(
      onHoverChanged: onHoverChanged,
      child: renderButton(
        configuration: GSIButtonConfiguration(
          minimumWidth: 400,
          shape: GSIButtonShape.pill,
          size: GSIButtonSize.large,
          text: GSIButtonText.signinWith,
          theme: GSIButtonTheme.filledBlack,
          type: GSIButtonType.standard,
          locale: 'en',
        ),
      ),
    );

class _HoverReportingButton extends StatefulWidget {
  const _HoverReportingButton(
      {required this.child, required this.onHoverChanged});

  final Widget child;
  final ValueChanged<bool> onHoverChanged;

  @override
  State<_HoverReportingButton> createState() => _HoverReportingButtonState();
}

class _HoverReportingButtonState extends State<_HoverReportingButton> {
  final _area = GlobalKey();
  late final JSFunction _onMouseMove = _handleMouseMove.toJS;
  late final JSFunction _onMouseLeave = _handleMouseLeave.toJS;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('mousemove', _onMouseMove);
    web.document.documentElement?.addEventListener('mouseleave', _onMouseLeave);
  }

  void _handleMouseMove(web.MouseEvent event) {
    final box = _area.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    _setHovering(Rect.fromPoints(topLeft, bottomRight)
        .contains(Offset(event.clientX.toDouble(), event.clientY.toDouble())));
  }

  void _handleMouseLeave(web.Event event) => _setHovering(false);

  void _setHovering(bool hovering) {
    if (hovering == _hovering) return;
    _hovering = hovering;
    widget.onHoverChanged(hovering);
  }

  @override
  void dispose() {
    web.window.removeEventListener('mousemove', _onMouseMove);
    web.document.documentElement
        ?.removeEventListener('mouseleave', _onMouseLeave);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _area, child: widget.child);
}
