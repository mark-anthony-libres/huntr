import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../../services/nearby_service.dart' show nearbyAgo;
import '../../theme.dart';
import '../explore/explore_map.dart' show MapTiles;

/// Roam's globe.
const roamIcon = Icons.public_rounded;

/// The map images Roam's maps use (tests put [MapTiles.none] here).
MapTiles Function() roamMapTiles = () => MapTiles.configured;

/// "Roaming": on someone's tile, pin and profile, while they roam. Tapped
/// (when [onTap] is set), it shows where.
class RoamingTag extends StatelessWidget {
  const RoamingTag({super.key, this.small = false, this.onTap, this.label});

  final bool small;
  final VoidCallback? onTap;

  /// Instead of "Roaming" (e.g. "Roaming in Shibuya").
  final String? label;

  /// Its text, sized to what fits: [label] in full, else "Roaming", else
  /// none (then no tag at all: a narrow tile or header).
  String? _fitting(BuildContext context, double width) {
    final style = _style;
    // the globe, the gaps and the arrow around the text
    final around = (small ? 5 + 12 + 3 + 7 : 9 + 16 + 5 + 11) +
        (onTap != null ? (small ? 16 : 20) : 0);
    for (final text in [if (label != null) label!, 'Roaming']) {
      final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1)
        ..layout();
      if (painter.width + around <= width) return text;
    }
    return null;
  }

  TextStyle get _style => TextStyle(
      color: Colors.black,
      fontSize: small ? 10.5 : 13,
      height: 1,
      fontWeight: FontWeight.w800);

  @override
  Widget build(BuildContext context) {
    final tag = LayoutBuilder(builder: (context, box) {
      final text = _fitting(context, box.maxWidth);
      // no room for "Roaming": nothing (the profile says it)
      if (text == null) return const SizedBox.shrink();
      return Container(
        key: const Key('roamingTag'),
        height: small ? 20 : 30,
        padding: EdgeInsets.fromLTRB(small ? 5 : 9, 0, small ? 7 : 11, 0),
        decoration: BoxDecoration(
          color: HuntrColors.orange,
          borderRadius: BorderRadius.circular(small ? 10 : 15),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(roamIcon, size: small ? 12 : 16, color: Colors.black),
          SizedBox(width: small ? 3 : 5),
          Flexible(
            child: Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: _style),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: small ? 14 : 18, color: Colors.black),
          ],
        ]),
      );
    });
    final described = Semantics(
      label: onTap == null ? 'Roaming' : null,
      child: tag,
    );
    if (onTap == null) return described;
    return Semantics(
      button: true,
      label: 'Where ${label ?? 'they are roaming'}',
      child: GestureDetector(onTap: onTap, child: tag),
    );
  }
}

/// Where [person] roams: the place, since when, the spot on a small map,
/// and that it's not where they are.
Future<void> showRoamWhere(BuildContext context, Profile person) {
  final roam = person.roaming;
  if (roam == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RoamWhereSheet(person: person, roam: roam),
  );
}

class RoamWhereSheet extends StatelessWidget {
  const RoamWhereSheet({super.key, required this.person, required this.roam});

  final Profile person;
  final RoamSpot roam;

  @override
  Widget build(BuildContext context) {
    final name = person.name.isEmpty ? 'They' : person.name;
    final since = roam.since;
    final spot = LatLng(roam.latitude, roam.longitude);
    final tiles = roamMapTiles();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          key: const Key('roamWhere'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$name ${person.name.isEmpty ? 'are' : 'is'} roaming',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            if (since != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    'Started roaming ${nearbyAgo(since, DateTime.now())}',
                    style: const TextStyle(color: HuntrColors.muted)),
              ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 190,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: spot,
                      initialZoom: 11,
                      backgroundColor: HuntrColors.surface,
                    ),
                    children: [
                      if (tiles.url.isNotEmpty)
                        TileLayer(
                          urlTemplate: tiles.url,
                          tileProvider: NetworkTileProvider(
                              attemptDecodeOfHttpErrorResponses: false),
                          userAgentPackageName: 'com.marklibres.huntr',
                          maxNativeZoom: tiles.maxNativeZoom,
                        ),
                      CircleLayer(circles: [
                        CircleMarker(
                          point: spot,
                          radius: 3000,
                          useRadiusInMeter: true,
                          color: HuntrColors.orange.withValues(alpha: 0.14),
                          borderColor:
                              HuntrColors.orange.withValues(alpha: 0.6),
                          borderStrokeWidth: 1.5,
                        ),
                      ]),
                      MarkerLayer(markers: [
                        Marker(
                          point: spot,
                          width: 18,
                          height: 18,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: HuntrColors.orange,
                              border: Border.all(
                                  color: HuntrColors.night, width: 3),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: HuntrColors.orange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(roamIcon, color: HuntrColors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(roam.place,
                        key: const Key('roamWherePlace'),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    if (roam.detail != null)
                      Text(roam.detail!,
                          style: const TextStyle(color: HuntrColors.muted)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HuntrColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 18, color: HuntrColors.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'This is the area $name chose to look around, not where '
                        '$name is. A location shared in chat is always real.',
                        style: const TextStyle(
                            color: HuntrColors.muted, height: 1.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explore's Roam button: "Roam" (plain) while I don't roam; the place, in
/// the accent, while I do. Opens the Roam screen.
class RoamButton extends StatelessWidget {
  const RoamButton({super.key, required this.roam, required this.onPressed});

  final RoamSpot? roam;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final on = roam != null;
    return Semantics(
      button: true,
      label: on ? 'Roaming in ${roam!.place}' : 'Roam',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 40,
        constraints: const BoxConstraints(maxWidth: 170),
        decoration: BoxDecoration(
          gradient: on ? HuntrColors.accentGradient : null,
          color: on ? null : HuntrColors.night.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: on
              ? null
              : Border.all(color: const Color(0xFF353944), width: 1.2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('roamButton'),
            borderRadius: BorderRadius.circular(20),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 14, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(roamIcon,
                    size: 18, color: on ? Colors.black : Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(on ? roam!.place : 'Roam',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: on ? Colors.black : Colors.white,
                          fontSize: 14,
                          fontWeight: on ? FontWeight.w800 : FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
