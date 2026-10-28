import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';

/// A profile's "looking for" choices (Expectation), in even columns as its
/// Stats: pills of one width, two across a phone and more on wider screens
/// (about [_minWidth] each), so none sits alone or gets squeezed.
class LookingForGrid extends StatelessWidget {
  const LookingForGrid({super.key, required this.choices});

  final Iterable<LookingFor> choices;

  static const _gap = 10.0, _minWidth = 130.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final across =
            ((box.maxWidth + _gap) / (_minWidth + _gap)).floor().clamp(2, 4);
        final width = (box.maxWidth - _gap * (across - 1)) / across;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final choice in choices)
              SizedBox(width: width, child: LookingForPill(choice: choice)),
          ],
        );
      });
}

/// One "looking for" choice on a profile: outlined pill with an orange icon,
/// filling the width it's given (a label too long for it shrinks to fit).
class LookingForPill extends StatelessWidget {
  const LookingForPill({super.key, required this.choice});

  final LookingFor choice;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('lookingFor-${choice.name}'),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF3A3B44)),
      ),
      child: Row(children: [
        Icon(choice.icon, size: 18, color: HuntrColors.orange),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(choice.label,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
