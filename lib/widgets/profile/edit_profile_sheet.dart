import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../services/huntr_backend.dart';
import '../../services/profile_service.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../pill_chip.dart';
import 'stats_editor.dart';

/// Opens Edit profile. The form is loaded from and saved to the backend;
/// a confirmation is shown only after the save succeeded.
Future<void> showEditProfileSheet(BuildContext context) async {
  final profiles = ServicesScope.profilesOf(context);
  final token = AppScope.read(context).sessionToken;
  final messenger = ScaffoldMessenger.of(context);
  if (profiles == null || token == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Editing your profile needs the Huntr server.')));
    return;
  }
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => EditProfileSheet(profiles: profiles, token: token),
  );
  if (saved == true) {
    messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
  }
}

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet(
      {super.key, required this.profiles, required this.token});

  final ProfileService profiles;
  final String token;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _form = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _age = TextEditingController();
  Set<LookingFor> _lookingFor = {};

  /// Stats as edited here (saved with the rest).
  ProfileStats _stats = const ProfileStats();

  /// Form limits from the backend; the form is only shown once they're known.
  ProfileConfig? _config;
  bool _loading = true;
  String? _loadError;

  bool _saving = false;
  String? _saveError;

  /// Server-side validation messages, by API field name.
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.profiles.fetchMine(widget.token),
        widget.profiles.fetchConfig(widget.token),
      ]);
      final profile = results[0] as MyProfile;
      if (!mounted) return;
      setState(() {
        _config = results[1] as ProfileConfig;
        _displayName.text = profile.displayName ?? '';
        _bio.text = profile.bio ?? '';
        _age.text = profile.age?.toString() ?? '';
        _lookingFor = LookingFor.fromNames(profile.lookingFor);
        _stats = profile.stats;
        _loading = false;
      });
    } on SessionRejectedException {
      _sessionExpired();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error is BackendException
            ? error.message
            : 'Your profile could not be loaded.';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _fieldErrors = {};
      _saveError = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.profiles.updateProfile(
        widget.token,
        ProfileEdit(
          displayName: _displayName.text,
          bio: _bio.text,
          age: int.parse(_age.text),
          lookingFor: _lookingFor,
          stats: _stats,
        ),
      );
      if (!mounted) return;
      // Show what the database now holds, not what was typed.
      AppScope.read(context).updateMe(
        name: saved.displayName ?? '',
        bio: saved.bio ?? '',
        age: saved.age,
        lookingFor: LookingFor.fromNames(saved.lookingFor),
      );
      AppScope.read(context).setMyStats(saved.stats);
      Navigator.of(context).pop(true);
    } on SessionRejectedException {
      _sessionExpired();
    } on ProfileValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = error.fieldErrors;
        _saveError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveError = error is BackendException
          ? error.message
          : 'Your profile could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _sessionExpired() {
    if (!mounted) return;
    final app = AppScope.read(context);
    Navigator.of(context).pop(false);
    app.endSession();
  }

  void _clearFieldError(String field) {
    if (_fieldErrors.containsKey(field)) {
      setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
    }
  }

  String? _validateAge(String? value, ProfileConfig config) {
    final age = int.tryParse(value ?? '');
    if (age == null) return 'Age is required';
    if (age < config.minAge || age > config.maxAge) {
      return 'Age must be between ${config.minAge} and ${config.maxAge}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: _loading
          ? const SizedBox(
              key: Key('editProfileLoading'),
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
              ? _LoadFailed(message: _loadError!, onRetry: _load)
              : _buildForm(context, _config!),
    );
  }

  Widget _buildForm(BuildContext context, ProfileConfig config) {
    // the title and Save stay in view; only the fields between them scroll
    return Form(
      key: _form,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text('Edit profile',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                key: const Key('closeEditProfile'),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ]),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LabeledField(
                      label: 'Display name',
                      child: TextFormField(
                        key: const Key('editDisplayName'),
                        controller: _displayName,
                        textCapitalization: TextCapitalization.words,
                        maxLength: config.displayNameMaxLength,
                        decoration: _borderedDecoration(
                          hint: 'Enter your display name',
                          error: _fieldErrors['display_name'],
                          prefixIcon: Icon(Icons.person_outline_rounded,
                              color: HuntrColors.orange),
                          suffixIcon: _displayName.text.isEmpty
                              ? null
                              : IconButton(
                                  key: const Key('clearDisplayName'),
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.cancel_rounded,
                                      size: 20, color: HuntrColors.muted),
                                  onPressed: () => setState(_displayName.clear),
                                ),
                        ),
                        buildCounter:
                            _characterCounter('editDisplayNameCounter'),
                        // the clear button comes and goes with the text
                        onChanged: (_) =>
                            setState(() => _clearFieldError('display_name')),
                      ),
                    ),
                    _LabeledField(
                      label: 'Bio',
                      child: TextFormField(
                        key: const Key('editBio'),
                        controller: _bio,
                        minLines: 4,
                        maxLines: 6,
                        maxLength: config.bioMaxLength,
                        decoration: _borderedDecoration(
                          hint: 'Tell people a little about yourself',
                          helper:
                              'Tell others about yourself. Be friendly and respectful.',
                          error: _fieldErrors['bio'],
                          prefixIcon: const Align(
                            alignment: Alignment.topCenter,
                            widthFactor: 1,
                            heightFactor: 1,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(12, 12, 10, 0),
                              child: _IconBox(icon: Icons.description_outlined),
                            ),
                          ),
                        ),
                        buildCounter: _characterCounter('editBioCounter'),
                        onChanged: (_) => _clearFieldError('bio'),
                      ),
                    ),
                    _LabeledField(
                      label: 'Age',
                      child: TextFormField(
                        key: const Key('editAge'),
                        controller: _age,
                        keyboardType: TextInputType.number,
                        // a number only, never more digits than the oldest age has
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                              '${config.maxAge}'.length),
                        ],
                        decoration: _borderedDecoration(
                          hint: '${config.minAge}–${config.maxAge}',
                          helper:
                              'You must be ${config.minAge} or older. This helps '
                              'others find people in their preferred age range.',
                          error: _fieldErrors['age'],
                          prefixIcon: Icon(Icons.calendar_today_outlined,
                              color: HuntrColors.orange, size: 20),
                        ),
                        validator: (value) => _validateAge(value, config),
                        onChanged: (_) => _clearFieldError('age'),
                      ),
                    ),
                    _LabeledField(
                      label: 'Sexual position',
                      info: 'Shown on your profile. Pick one, or Do not show.',
                      child: Wrap(
                        key: const Key('editPosition'),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final position in [
                            ...SexualPosition.values,
                            null
                          ])
                            PillChip(
                              key: Key(
                                  'position-${position?.apiName ?? 'none'}'),
                              icon: _positionIcons[position]!,
                              label: position?.label ?? 'Do not show',
                              selected: _stats.sexualPosition == position,
                              onSelected: (_) => setState(
                                  () => _stats = _stats.withPosition(position)),
                            ),
                        ],
                      ),
                    ),
                    _LabeledField(
                      label: 'Looking for',
                      info: 'Pick everything you are open to.',
                      child: Column(
                        key: const Key('editLookingFor'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final choice in LookingFor.values)
                                PillChip(
                                  icon: choice.icon,
                                  label: choice.label,
                                  selected: _lookingFor.contains(choice),
                                  onSelected: (selected) => setState(() {
                                    _lookingFor = {..._lookingFor};
                                    selected
                                        ? _lookingFor.add(choice)
                                        : _lookingFor.remove(choice);
                                    _clearFieldError('looking_for');
                                  }),
                                ),
                            ],
                          ),
                          if (_fieldErrors['looking_for'] case final error?)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 4),
                              child: Text(error,
                                  style: const TextStyle(color: _errorColor)),
                            ),
                        ],
                      ),
                    ),
                    // height, weight, body type, ... (and Show Age, units)
                    StatsEditor(
                      stats: _stats,
                      onChanged: (stats) => setState(() => _stats = stats),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _saveError!,
                  key: const Key('editProfileError'),
                  style: const TextStyle(color: _errorColor),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: HuntrColors.accentGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: FilledButton(
                key: const Key('saveProfile'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontFamily: huntrFontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save changes'),
              ),
            ),
          ]),
    );
  }
}

/// An icon for each position chip (null: Do not show).
const _positionIcons = <SexualPosition?, IconData>{
  SexualPosition.top: Icons.arrow_upward_rounded,
  SexualPosition.bottom: Icons.arrow_downward_rounded,
  SexualPosition.versatile: Icons.swap_vert_rounded,
  SexualPosition.versBottom: Icons.south_east_rounded,
  SexualPosition.versTop: Icons.north_east_rounded,
  SexualPosition.side: Icons.swap_horiz_rounded,
  null: Icons.visibility_off_outlined,
};

const _errorColor = Color(0xFFFF9B8A);

/// "12 / 50" under a field with a character limit.
InputCounterWidgetBuilder _characterCounter(String key) =>
    (context, {required currentLength, required isFocused, maxLength}) => Text(
        '$currentLength / $maxLength',
        key: Key(key),
        style: const TextStyle(color: HuntrColors.muted));

/// Bordered input look for the sheet. The app theme's fields are filled with
/// the surface colour and have no border, which makes them invisible on this
/// surface-coloured sheet.
InputDecoration _borderedDecoration({
  String? hint,
  String? helper,
  String? error,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    helperStyle: const TextStyle(color: HuntrColors.muted),
    errorText: error,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: HuntrColors.night,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: outline(const Color(0xFF353944), 1.2),
    enabledBorder: outline(const Color(0xFF353944), 1.2),
    focusedBorder: outline(HuntrColors.orange, 1.6),
    errorBorder: outline(_errorColor, 1.2),
    focusedErrorBorder: outline(_errorColor, 1.6),
    errorStyle: const TextStyle(color: _errorColor),
  );
}

/// An orange icon in a rounded square (the bio field's icon).
class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: HuntrColors.orange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: HuntrColors.orange),
    );
  }
}

/// A label above its input, so the label never looks like the field; an
/// optional ⓘ next to it explains the choice.
class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child, this.info});

  final String label;
  final String? info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (info != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: info!,
                triggerMode: TooltipTriggerMode.tap,
                child: const Icon(Icons.info_outline_rounded,
                    size: 17, color: HuntrColors.muted),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message,
              key: const Key('editProfileLoadError'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: HuntrColors.muted)),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('editProfileRetry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
