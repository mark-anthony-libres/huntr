import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Three short steps: what Huntr is, who you are, what you're looking for.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _page = 0;
  int _age = 24;
  bool _confirmedAdult = false;
  final Set<LookingFor> _looking = {LookingFor.chat, LookingFor.friends};

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_page) {
        0 => true,
        1 => _name.text.trim().isNotEmpty && _confirmedAdult,
        _ => _looking.isNotEmpty,
      };

  void _next() {
    FocusScope.of(context).unfocus();
    if (_page < 2) {
      _pages.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
    } else {
      AppScope.read(context).completeOnboarding(
          name: _name.text, age: _age, lookingFor: _looking);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient:
                            i <= _page ? HuntrColors.accentGradient : null,
                        color: i <= _page ? null : HuntrColors.surfaceHigh,
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  // 1. welcome
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: HuntrColors.accentGradient,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.radar,
                              size: 40, color: Colors.black),
                        ),
                        const SizedBox(height: 28),
                        Text('Meet people\nright around you.',
                            style: text.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800, height: 1.05)),
                        const SizedBox(height: 16),
                        const Text(
                          'See who\'s nearby, say hi with one tap, and chat when it clicks. '
                          'You decide what others see.',
                          style: TextStyle(
                              fontSize: 16,
                              color: HuntrColors.muted,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),

                  // 2. about you
                  ListView(
                    padding: const EdgeInsets.all(28),
                    children: [
                      const SizedBox(height: 24),
                      Text('What should we call you?',
                          style: text.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('onboardName'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(hintText: 'Your first name'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 28),
                      Text('Age: $_age', style: text.titleMedium),
                      Slider(
                        value: _age.toDouble(),
                        min: 18,
                        max: 70,
                        divisions: 52,
                        label: '$_age',
                        onChanged: (v) => setState(() => _age = v.round()),
                      ),
                      CheckboxListTile(
                        key: const Key('onboardAdult'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _confirmedAdult,
                        onChanged: (v) =>
                            setState(() => _confirmedAdult = v ?? false),
                        title: const Text('I confirm I\'m 18 or older'),
                      ),
                    ],
                  ),

                  // 3. looking for
                  ListView(
                    padding: const EdgeInsets.all(28),
                    children: [
                      const SizedBox(height: 24),
                      Text('What are you here for?',
                          style: text.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                          'Pick as many as you like. You can change this anytime.',
                          style: TextStyle(color: HuntrColors.muted)),
                      const SizedBox(height: 20),
                      for (final l in LookingFor.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ChoiceCard(
                            icon: l.icon,
                            label: l.label,
                            selected: _looking.contains(l),
                            onTap: () => setState(() => _looking.contains(l)
                                ? _looking.remove(l)
                                : _looking.add(l)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () => _pages.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('onboardNext'),
                    onPressed: _canContinue ? _next : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(_page == 0
                          ? 'Get started'
                          : _page == 1
                              ? 'Continue'
                              : 'Start exploring'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? HuntrColors.amber.withValues(alpha: 0.14)
          : HuntrColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? HuntrColors.amber : Colors.transparent,
            width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            Icon(icon, color: selected ? HuntrColors.amber : HuntrColors.muted),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600))),
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? HuntrColors.amber : HuntrColors.muted),
          ]),
        ),
      ),
    );
  }
}
