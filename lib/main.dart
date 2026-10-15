import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() => runApp(HuntrApp(state: AppState()));

class HuntrApp extends StatelessWidget {
  const HuntrApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Huntr',
        debugShowCheckedModeBanner: false,
        theme: buildHuntrTheme(),
        home: Builder(
          builder: (context) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: AppScope.of(context).onboarded ? const HomeShell() : const OnboardingScreen(),
          ),
        ),
      ),
    );
  }
}
