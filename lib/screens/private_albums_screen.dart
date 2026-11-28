import 'package:flutter/material.dart';

import '../widgets/me/my_albums_section.dart';

/// Me > Private albums: my albums, a new one, and how they work (the ⓘ).
class PrivateAlbumsScreen extends StatelessWidget {
  const PrivateAlbumsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Private albums')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: const [MyAlbumsSection()],
            ),
          ),
        ),
      ),
    );
  }
}
