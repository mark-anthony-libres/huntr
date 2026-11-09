import 'package:flutter/material.dart';

import '../theme.dart';

/// A light map made dark: its brightness turned around (light ground goes
/// near black, dark names go bright) and coloured from the app's night
/// towards its accent, so it wears the chosen theme. One filter over all of
/// a map's images (wrap the tile layer, not each image).
Widget nightMap(Widget map) {
  final accent = HuntrColors.orange;
  final ground = HuntrColors.night;
  // per channel: the ground, plus (how dark it was) x (a little grey and
  // half the accent)
  List<double> row(double accentChannel, double groundChannel) {
    final reach = 0.35 * 255 + 0.45 * accentChannel * 255;
    return [
      -reach * 0.2126 / 255,
      -reach * 0.7152 / 255,
      -reach * 0.0722 / 255,
      0,
      groundChannel * 255 + reach,
    ];
  }

  return ColorFiltered(
    colorFilter: ColorFilter.matrix([
      ...row(accent.r, ground.r),
      ...row(accent.g, ground.g),
      ...row(accent.b, ground.b),
      0,
      0,
      0,
      1,
      0,
    ]),
    child: map,
  );
}
