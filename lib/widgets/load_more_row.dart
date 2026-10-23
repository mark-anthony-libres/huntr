import 'package:flutter/material.dart';

import '../theme.dart';

/// A spinner at the end of a list that loads in pages: being built (it's
/// near the screen) asks for the next page, once.
class LoadMoreRow extends StatefulWidget {
  const LoadMoreRow({super.key, required this.onVisible});

  final VoidCallback onVisible;

  @override
  State<LoadMoreRow> createState() => _LoadMoreRowState();
}

class _LoadMoreRowState extends State<LoadMoreRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: HuntrColors.orange),
          ),
        ),
      );
}
