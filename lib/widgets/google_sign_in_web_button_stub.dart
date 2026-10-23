import 'package:flutter/widgets.dart';

/// Only the web build renders Google's own button.
Widget buildGoogleSignInButton({required ValueChanged<bool> onHoverChanged}) =>
    const SizedBox.shrink();
