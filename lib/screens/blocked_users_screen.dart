import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../state/app_state.dart';
import '../state/block_state.dart';
import '../state/messaging_state.dart';
import '../widgets/block_gate.dart' show formatBlockDate;
import '../widgets/me/section_states.dart';
import '../widgets/me/person_list_row.dart';

/// The people I block (only mine), each with when I can unblock them. The
/// backend decides when that is; Unblock stays off until then.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedPerson>? _people;
  String? _error;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final blocks = BlockScope.read(context);
    if (blocks == null) return;
    setState(() => _error = null);
    try {
      final people = await blocks.mine();
      if (mounted) setState(() => _people = people);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Check your connection and try again.');
      }
    }
  }

  Future<void> _unblock(BlockedPerson person) async {
    final blocks = BlockScope.read(context)!;
    final app = AppScope.read(context);
    final messaging = MessagingScope.read(context);
    setState(() => _unblocking.add(person.ref));
    try {
      if (person.userId case final userId?) {
        await blocks.unblock(userId);
        app.unblock('user-$userId');
      } else {
        // someone I only know anonymously: by their conversation
        await blocks.unblockAnonymous(person.anonymousConversationId!);
      }
      await messaging?.refresh();
      await _load();
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(person.ref));
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: LoadFailedCard(
            title: 'Couldn’t load blocked users',
            message: _error!,
            onRetry: _load,
            retryKey: const Key('blockedRetry')),
      );
    } else if (people == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (people.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyStateCard(
            key: Key('noBlockedUsers'),
            icon: Icons.block_rounded,
            title: 'Nobody blocked',
            message: 'People you block show up here.'),
      );
    } else {
      body = ListView.separated(
        key: const Key('blockedList'),
        padding: const EdgeInsets.all(16),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = people[i];
          final busy = _unblocking.contains(p.ref);
          return PersonListRow(
            key: Key('blocked-${p.ref}'),
            name: p.name,
            photoUrl: p.photoUrl,
            anonymousAvatar: p.anonymousAvatar,
            status: p.canUnblock
                ? 'Blocked ${formatBlockDate(p.blockedAt)} · can be unblocked'
                : 'Blocked ${formatBlockDate(p.blockedAt)} · '
                    'unblock from ${formatBlockDate(p.unblockAvailableAt)}',
            statusKey: Key('blockedStatus-${p.ref}'),
            actionLabel: 'Unblock',
            actionKey: Key('unblock-${p.ref}'),
            busy: busy,
            onAction: p.canUnblock ? () => _unblock(p) : null,
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: body,
    );
  }
}
