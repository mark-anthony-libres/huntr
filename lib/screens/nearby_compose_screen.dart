import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../services/nearby_service.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/nearby/nearby_post_card.dart';

/// Writing a Nearby post: up to [NearbyService.maxLength] characters, how
/// far it reaches (500 m to 10 km), and how it will look - under a random
/// name and animal. Pops with the post once it's up.
class NearbyComposeScreen extends StatefulWidget {
  const NearbyComposeScreen({super.key});

  @override
  State<NearbyComposeScreen> createState() => _NearbyComposeScreenState();
}

class _NearbyComposeScreenState extends State<NearbyComposeScreen> {
  final _text = TextEditingController();

  /// Index into [NearbyService.radii] (5 km by default).
  int _radius = 3;

  /// The random name it'll be posted under (from the backend).
  NearbyName? _as;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickName());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickName() async {
    final service = ServicesScope.nearbyOf(context);
    final token = AppScope.read(context).sessionToken;
    if (service == null || token == null) return;
    try {
      final name = await service.previewName(token);
      if (mounted) setState(() => _as = name);
    } catch (error) {
      debugPrint('Nearby name not picked: $error');
    }
  }

  bool get _ready {
    final length = _text.text.trim().length;
    return length > 0 && _text.text.length <= NearbyService.maxLength;
  }

  Future<void> _post() async {
    final service = ServicesScope.nearbyOf(context);
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (!_ready || _posting || service == null || token == null) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      final post = await service.post(token,
          body: _text.text, radiusM: NearbyService.radii[_radius], as: _as);
      if (mounted) Navigator.of(context).pop(post);
    } on SessionRejectedException {
      if (mounted) app.endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : "Your post didn't go up. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _text.text.length;
    final over = count > NearbyService.maxLength;
    final as = _as;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('nearbyComposeClose'),
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Create Post'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              key: const Key('nearbyPost'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 22)),
              onPressed: _ready && !_posting ? _post : null,
              child: _posting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // ---- what's on my mind ----
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: Column(children: [
                    TextField(
                      key: const Key('nearbyText'),
                      controller: _text,
                      autofocus: true,
                      minLines: 5,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: "What's on your mind?\nShare something with "
                            'people nearby…',
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('$count/${NearbyService.maxLength}',
                          key: const Key('nearbyCount'),
                          style: TextStyle(
                              color:
                                  over ? HuntrColors.coral : HuntrColors.muted,
                              fontSize: 13)),
                    ),
                  ]),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!,
                        key: const Key('nearbyPostError'),
                        style: const TextStyle(color: HuntrColors.coral)),
                  ),
                const SizedBox(height: 22),

                // ---- how far it reaches ----
                Row(children: [
                  Icon(Icons.location_on_rounded, color: HuntrColors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Broadcast to people nearby',
                        style: TextStyle(fontSize: 16)),
                  ),
                  const Tooltip(
                    message: 'Only people this close to where you post can '
                        'see it.',
                    child: Icon(Icons.help_outline_rounded,
                        color: HuntrColors.muted),
                  ),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: HuntrColors.border),
                  ),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.location_on_outlined),
                      const SizedBox(width: 8),
                      Text(
                          'Within ${nearbyRadiusLabel(NearbyService.radii[_radius])}',
                          key: const Key('nearbyRadiusLabel'),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ]),
                    Slider(
                      key: const Key('nearbyRadius'),
                      value: _radius.toDouble(),
                      min: 0,
                      max: (NearbyService.radii.length - 1).toDouble(),
                      divisions: NearbyService.radii.length - 1,
                      activeColor: HuntrColors.orange,
                      label: nearbyRadiusLabel(NearbyService.radii[_radius]),
                      onChanged: (v) => setState(() => _radius = v.round()),
                    ),
                    Row(children: [
                      for (final (i, m) in NearbyService.radii.indexed)
                        Expanded(
                          child: Text(nearbyRadiusLabel(m),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: i == _radius
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: i == _radius
                                      ? Colors.white
                                      : HuntrColors.muted)),
                        ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 22),

                // ---- how it will look ----
                const Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Preview ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: '(anonymous)',
                      style: TextStyle(color: HuntrColors.muted)),
                ])),
                const SizedBox(height: 10),
                Container(
                  key: const Key('nearbyPreview'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HuntrColors.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          NearbyAvatar(animal: as?.avatar ?? 'fox', size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(as?.name ?? 'A random name',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      'Within ${nearbyRadiusLabel(NearbyService.radii[_radius])} · Just now',
                                      style: const TextStyle(
                                          color: HuntrColors.muted,
                                          fontSize: 13)),
                                ]),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                            _text.text.trim().isEmpty
                                ? 'This is how your post will appear to others '
                                    '(with a random name and avatar).'
                                : _text.text.trim(),
                            style: const TextStyle(fontSize: 16, height: 1.4)),
                      ]),
                ),
                const SizedBox(height: 26),

                // ---- what anonymous means here ----
                const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Promise(
                          icon: Icons.theater_comedy_outlined,
                          text: 'Your identity will always be anonymous.'),
                      _Promise(
                          icon: Icons.radar_rounded,
                          text: 'Only visible to people within the selected '
                              'distance.'),
                      _Promise(
                          icon: Icons.forum_outlined,
                          text: 'Others can comment and reply anonymously '
                              'too.'),
                    ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(children: [
            Icon(icon, size: 30, color: HuntrColors.muted),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: HuntrColors.muted, fontSize: 13, height: 1.35)),
          ]),
        ),
      );
}
