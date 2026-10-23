import 'package:flutter/material.dart';

import '../services/huntr_backend.dart';
import '../state/messaging_state.dart';
import '../widgets/block_gate.dart' show formatBlockDate;
import '../widgets/me/person_list_row.dart';
import '../widgets/me/section_states.dart';
import 'anonymous_profile_screen.dart';
import 'profile_screen.dart';

/// The people I unmatched (only mine). Each can be removed from the list at
/// any time, and opened: their profile with "Remove from Unmatch List"
/// instead of Message (the only way to see it while unmatched), or - someone
/// I only know anonymously - their anonymous profile.
class UnmatchedUsersScreen extends StatefulWidget {
  const UnmatchedUsersScreen({super.key});

  @override
  State<UnmatchedUsersScreen> createState() => _UnmatchedUsersScreenState();
}

class _UnmatchedUsersScreenState extends State<UnmatchedUsersScreen> {
  List<UnmatchedPerson>? _people;
  String? _error;
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final messaging = MessagingScope.read(context);
    if (messaging == null) return;
    setState(() => _error = null);
    try {
      final people = await messaging.unmatches();
      if (mounted) setState(() => _people = people ?? const []);
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Check your connection and try again.');
      }
    }
  }

  Future<void> _remove(UnmatchedPerson person) async {
    final messaging = MessagingScope.read(context)!;
    setState(() => _removing.add(person.ref));
    try {
      await messaging.removeUnmatch(
          userId: person.userId,
          anonymousConversationId: person.anonymousConversationId);
      await _load();
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _removing.remove(person.ref));
    }
  }

  Future<void> _open(UnmatchedPerson person) async {
    final messaging = MessagingScope.read(context)!;
    final navigator = Navigator.of(context);
    Widget? screen;
    if (person.anonymousConversationId case final conversationId?) {
      screen = AnonymousProfileScreen(conversationId: conversationId);
    } else {
      try {
        final profile = await messaging.unmatchedProfile(person.userId!);
        if (profile != null) screen = ProfileScreen.person(person: profile);
      } on BackendException catch (e) {
        // e.g. a block between us comes first
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    if (screen == null || !mounted) return;
    await navigator.push(MaterialPageRoute(builder: (_) => screen!));
    // they may have been removed from the list there
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: LoadFailedCard(
            title: 'Couldn’t load unmatched users',
            message: _error!,
            onRetry: _load,
            retryKey: const Key('unmatchedRetry')),
      );
    } else if (people == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (people.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyStateCard(
            key: Key('noUnmatchedUsers'),
            icon: Icons.person_remove_outlined,
            title: 'All clear ✨',
            message: 'You haven’t unmatched anyone. If you do, they’ll show '
                'up here, and you can bring them back anytime.'),
      );
    } else {
      body = ListView.separated(
        key: const Key('unmatchedList'),
        padding: const EdgeInsets.all(16),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = people[i];
          return PersonListRow(
            key: Key('unmatched-${p.ref}'),
            name: p.name,
            photoUrl: p.photoUrl,
            anonymousAvatar: p.anonymousAvatar,
            status: p.isAnonymous
                ? 'Anonymous · unmatched ${formatBlockDate(p.unmatchedAt)}'
                : 'Unmatched ${formatBlockDate(p.unmatchedAt)}',
            actionLabel: 'Remove',
            actionKey: Key('removeUnmatch-${p.ref}'),
            busy: _removing.contains(p.ref),
            onAction: () => _remove(p),
            onTap: () => _open(p),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Unmatched users')),
      body: body,
    );
  }
}
