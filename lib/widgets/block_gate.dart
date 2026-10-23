import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../state/block_state.dart';
import '../theme.dart';

/// A screen about one person (their profile) that a block closes: like the
/// location gate, it shows [BlockedScreen] instead of [child] while either of
/// us blocks the other. Checked again with the backend every time it opens
/// (cached profiles, Explore results, links and stale screens all come
/// through here), and whenever a block changes.
class BlockGate extends StatefulWidget {
  const BlockGate({super.key, required this.userId, required this.child});

  /// Their backend id (null: a sample profile, never blocked here).
  final int? userId;
  final Widget child;

  @override
  State<BlockGate> createState() => _BlockGateState();
}

class _BlockGateState extends State<BlockGate> {
  @override
  void initState() {
    super.initState();
    final id = widget.userId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) BlockScope.read(context)?.check(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.userId;
    final status = id == null ? null : BlockScope.of(context)?.statusOf(id);
    if (status != null && status.blocked) return BlockedScreen(status: status);
    return widget.child;
  }
}

/// All that's shown of a person while a block is between us. To the person
/// blocked: only "You are blocked by this person".
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key, required this.status});

  final BlockStatus status;

  @override
  Widget build(BuildContext context) {
    final byMe = status.blockedByMe && !status.blockedMe;
    final until = status.unblockAvailableAt;
    return Scaffold(
      key: const Key('blockedScreen'),
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.block_rounded,
                  size: 52, color: HuntrColors.muted),
              const SizedBox(height: 20),
              Text(byMe ? blockedByMeMessage : blockedByThemMessage,
                  key: const Key('blockedMessage'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              if (byMe) ...[
                const SizedBox(height: 10),
                Text(
                    until == null || status.canUnblock
                        ? 'You can unblock them in Me → Blocked users.'
                        : 'You can unblock them from ${formatBlockDate(until)}, '
                            'in Me → Blocked users.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: HuntrColors.muted)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// "20 Nov 2026".
String formatBlockDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// "Block this user?" with what it means; true when confirmed.
Future<bool> confirmBlock(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('confirmBlockDialog'),
        title: const Text('Block this user?'),
        content: const SingleChildScrollView(
          child: Text(
              'If you block this person, neither of you will be able to '
              'message or interact with each other. They will no longer be '
              'able to find or access your profile through Explore or '
              'interact with your profile, and you will not be able to '
              'interact with theirs either. Your previous chat history will '
              'remain available, and albums they have not opened will remain '
              'visible according to the existing album access rules.\n\n'
              'You will not be able to unblock this person for 30 days.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirmBlock'),
            style: FilledButton.styleFrom(
                backgroundColor: HuntrColors.coral,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block User'),
          ),
        ],
      ),
    ) ==
    true;
