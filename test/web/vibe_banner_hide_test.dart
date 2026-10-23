// Runs in a browser only: flutter test --platform chrome test/web
@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/data/sample_data.dart';
import 'package:huntr/widgets/explore/vibe_banner.dart';

void main() {
  testWidgets('on web "Find your vibe" has a Hide button and no swipe',
      (tester) async {
    var hidden = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VibeBanner(
          people: buildSampleProfiles().take(3).toList(),
          onTap: () {},
          onHide: () => hidden = true,
        ),
      ),
    ));

    expect(find.byKey(const Key('dismissVibeBanner')), findsNothing);
    await tester.tap(find.byKey(const Key('hideVibeBanner')));
    expect(hidden, isTrue);
  });
}
