import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/location_service.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/onboarding/choice_card.dart';
import '../widgets/me/profile_photos_section.dart';
import '../widgets/onboarding/nearby_radar.dart';

/// Short steps: what Huntr is, who you are, your photos (at least one), what
/// you're looking for, and where you are. Without the photo service (tests,
/// sample data) there's no photo step.
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

  /// The photo step is there when photos can be uploaded.
  bool _withPhotos = false;

  List<_Step> get _steps => [
        _Step.welcome,
        _Step.about,
        if (_withPhotos) _Step.photos,
        _Step.lookingFor,
        _Step.location,
      ];

  int get _lastPage => _steps.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _withPhotos = ServicesScope.photosOf(context) != null;
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_steps[_page]) {
        _Step.welcome => true,
        _Step.about => _confirmedAdult,
        _Step.photos => AppScope.of(context).profilePhotos.isNotEmpty,
        _Step.lookingFor => _looking.isNotEmpty,
        _Step.location => _location != null && !_saving,
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
        // a comfortable width on tablets and computers
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
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
                      // 1. welcome: who's around, and a warm hello
                      Center(
                        key: const Key('onboardWelcome'),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: Column(
                              children: [
                                const NearbyRadar(size: 290),
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: HuntrColors.orange
                                        .withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text('People around you',
                                      style: TextStyle(
                                          color: HuntrColors.orange,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(height: 16),
                                Text('Who\'s around?',
                                    textAlign: TextAlign.center,
                                    style: text.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 14),
                                Text('You might find someone interesting.',
                                    textAlign: TextAlign.center,
                                    style: text.titleLarge?.copyWith(
                                        color: HuntrColors.orange,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 14),
                                const Text(
                                  'See who\'s nearby, check out their profiles, '
                                  'and say hello if someone catches your '
                                  'attention. You never know who you might meet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 15.5,
                                      color: HuntrColors.muted,
                                      height: 1.6),
                                ),
                                const SizedBox(height: 20),
                                const Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _Promise('Free to use',
                                        icon: Icons.favorite_rounded),
                                    _Promise('18+ only'),
                                    _Promise('Your choice, your pace'),
                                  ],
                                ),
                              ],
                            ),
                          ),
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
                          const SizedBox(height: 6),
                          const Text(
                              'Your first name, a nickname, or nothing at all. '
                              'You can change it anytime.',
                              style: TextStyle(color: HuntrColors.muted)),
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

                      // 3. photos: at least one, so people know who's saying hi
                      if (_withPhotos)
                        ListView(
                          key: const Key('onboardPhotos'),
                          padding: const EdgeInsets.all(28),
                          children: [
                            const SizedBox(height: 24),
                            Text('Add your photos',
                                style: text.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            const Text(
                                'Add at least one photo of yourself. The first one is your main photo. You can change them anytime.',
                                style: TextStyle(color: HuntrColors.muted)),
                            const SizedBox(height: 20),
                            const ProfilePhotosSection(showHeading: false),
                          ],
                        ),

                      // 4. looking for
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

                      // 5. location
                      ListView(
                        padding: const EdgeInsets.all(28),
                        children: [
                          const SizedBox(height: 24),
                          Text('Turn on your location',
                              style: text.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          const Text(
                              'HUNTR shows people near you, so it needs your location. Others only see roughly how far away you are, and you can hide that too.',
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
                      if (_page > 0) const Spacer(),
                      // the welcome's button fills the width
                      Expanded(
                        flex: _page == 0 ? 1 : 0,
                        child: FilledButton(
                          key: const Key('onboardNext'),
                          onPressed: _canContinue ? _next : null,
                          style: _page == 0
                              ? FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(60),
                                  textStyle: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600))
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(_page == 0
                                ? 'Explore nearby'
                                : _page < _lastPage
                                    ? 'Continue'
                                    : _saving
                                        ? 'Saving...'
                                        : 'Start exploring'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { welcome, about, photos, lookingFor, location }

/// A small promise under the welcome (free, adults only, your choice).
class _Promise extends StatelessWidget {
  const _Promise(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: HuntrColors.surfaceHigh,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon case final icon?) ...[
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
