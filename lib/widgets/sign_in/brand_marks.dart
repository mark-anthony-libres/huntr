import 'package:flutter/material.dart';

const double brandMarkSize = 30;

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/google_g_logo.png',
      key: const Key('googleLogo'),
      width: brandMarkSize,
      height: brandMarkSize,
      semanticLabel: 'Google logo',
    );
  }
}
