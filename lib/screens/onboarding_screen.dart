import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/onboarding/choice_card.dart';

/// Four short steps: what Huntr is, who you are, what you're looking for,
/// and where you are.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.locate = locateDevice,
    this.displayNameMaxLength,
  });

  /// Saves the answers. Throwing keeps the user on the last step with the
  /// error's message shown.
  final Future<void> Function(OnboardingAnswers answers) onFinished;

  final LocateDevice locate;

  /// The backend's display name limit; null when no backend is used.
  final int? displayNameMaxLength;

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
  GeoPoint? _location;
  bool _locating = false;
  bool _saving = false;
  String? _error;

  static const _lastPage = 3;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_page) {
        0 => true,
        1 => _confirmedAdult,
        2 => _looking.isNotEmpty,
        _ => _location != null && !_saving,
      };

  Future<void> _findLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final location = await widget.locate();
      if (mounted) setState(() => _location = location);
    } on LocationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_page < _lastPage) {
      await _pages.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onFinished(OnboardingAnswers(
        displayName: _name.text,
        age: _age,
        location: _location!,
        lookingFor: _looking,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is BackendException
            ? e.message
            : 'Your profile could not be saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
                children: List.generate(_lastPage + 1, (i) {
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
                        Image.asset(
                          'assets/huntr_logo.png',
                          height: 76,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          semanticLabel: 'Huntr logo',
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
                        maxLength: widget.displayNameMaxLength,
                        decoration: const InputDecoration(
                          labelText: 'Display name (optional)',
                          hintText: 'Your display name',
                        ),
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
                          child: ChoiceCard(
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

                  // 4. location
                  ListView(
                    padding: const EdgeInsets.all(28),
                    children: [
                      const SizedBox(height: 24),
                      Text('Where are you?',
                          style: text.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                          'Huntr shows you people nearby, so it needs your '
                          'location.',
                          style: TextStyle(color: HuntrColors.muted)),
                      const SizedBox(height: 20),
                      ChoiceCard(
                        key: const Key('onboardLocation'),
                        icon: _location == null
                            ? Icons.my_location
                            : Icons.location_on,
                        label: _locating
                            ? 'Finding your location...'
                            : _location == null
                                ? 'Share my location'
                                : 'Location found',
                        selected: _location != null,
                        onTap: _locating ? () {} : _findLocation,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
                child: Text(
                  _error!,
                  key: const Key('onboardError'),
                  style: const TextStyle(color: Color(0xFFFF9B8A)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => _pages.previousPage(
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
                          : _page < _lastPage
                              ? 'Continue'
                              : _saving
                                  ? 'Saving...'
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
