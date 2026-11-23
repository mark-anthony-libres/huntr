import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/changelog_service.dart';
import '../services/huntr_backend.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/changelog/changelog_body.dart';
import '../widgets/load_more_row.dart';
import '../widgets/me/section_states.dart';

/// The changelog on the web (the same entries).
final changelogWebsite = Uri.parse('https://web.huntr.online/changelog');

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// "23 November 2026"
String _date(DateTime when) {
  final local = when.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Asks once (after the home screen opens) whether there's news: sets
/// Settings' dot, and shows the newest entry marked for the app in the
/// What's new sheet - once: it counts as seen when shown.
Future<void> checkWhatsNew(BuildContext context) async {
  final service = ServicesScope.changelogOf(context);
  final app = AppScope.read(context);
  final token = app.sessionToken;
  if (service == null || token == null) return;
  try {
    final news = await service.news(token);
    if (!context.mounted) return;
    app.setWhatsNewUnseen(news.unseen);
    final entry = news.sheet;
    if (entry == null) return;
    final backendUrl = await service.backendUrl();
    if (!context.mounted) return;
    // seen as soon as it's shown (closing it any way counts)
    unawaited(service.markSeen(token, entry.id).then(
        (after) => app.setWhatsNewUnseen(after.unseen),
        onError: (Object _) {}));
    await showWhatsNewSheet(context, entry: entry, backendUrl: backendUrl);
  } catch (_) {
    // no news is fine: it's asked again next time
  }
}

/// The What's new sheet: one entry, Got it, and See all changes.
Future<void> showWhatsNewSheet(BuildContext context,
        {required ChangelogEntry entry, required String backendUrl}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: HuntrColors.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheet) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
        child: SafeArea(
          child: Column(
            key: const Key('whatsNewSheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: HuntrColors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text("WHAT'S NEW",
                      style: TextStyle(
                          color: HuntrColors.orange,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: _EntryContent(entry: entry, backendUrl: backendUrl),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('whatsNewSeeAll'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: HuntrColors.border),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const WhatsNewScreen()));
                      },
                      child: const Text('See all changes',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('whatsNewGotIt'),
                      style: FilledButton.styleFrom(
                        backgroundColor: HuntrColors.orange,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.of(sheet).pop(),
                      child: const Text('Got it',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

/// An entry's version and date, title, and text.
class _EntryContent extends StatelessWidget {
  const _EntryContent({required this.entry, required this.backendUrl});

  final ChangelogEntry entry;
  final String backendUrl;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              if (entry.version != null) ...[
                TextSpan(
                    text: entry.version!.toUpperCase(),
                    style: TextStyle(
                        color: HuntrColors.orange,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1)),
                const TextSpan(text: '  ·  '),
              ],
              TextSpan(text: _date(entry.publishedAt)),
            ]),
            style: const TextStyle(
                color: HuntrColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(entry.title,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 12),
          ChangelogBody(html: entry.bodyHtml, backendUrl: backendUrl),
        ],
      );
}

/// What's new (Settings): every published entry, newest first, a page at a
/// time. Opening it counts them as seen (Settings' dot goes).
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  List<ChangelogEntry>? _entries;
  int? _next = 0;
  bool _loading = false;
  String? _error;
  String? _backendUrl;

  ChangelogService? get _service => ServicesScope.changelogOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool more = false}) async {
    final service = _service;
    final app = AppScope.read(context);
    final token = app.sessionToken;
    final offset = more ? _next : 0;
    if (service == null || token == null || offset == null || _loading) {
      return;
    }
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      _backendUrl ??= await service.backendUrl();
      final page = await service.entries(token, offset: offset);
      if (!mounted) return;
      setState(() {
        _entries = [if (more) ...?_entries, ...page.entries];
        _next = page.nextOffset;
      });
      // seen: the newest is on screen
      if (!more && page.entries.isNotEmpty) {
        unawaited(service.markSeen(token, page.entries.first.id).then(
            (after) => app.setWhatsNewUnseen(after.unseen),
            onError: (Object _) {}));
      }
    } on SessionRejectedException {
      if (mounted) AppScope.read(context).endSession();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is BackendException
            ? error.message
            : 'Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text("What's new"),
        actions: [
          IconButton(
            tooltip: 'Open on the web',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => launchUrl(changelogWebsite,
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: HuntrColors.orange,
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              key: const Key('whatsNewList'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (entries == null && _error != null)
                  LoadFailedCard(
                      title: "What's new couldn't load",
                      message: _error!,
                      onRetry: _load)
                else if (entries == null)
                  const LoadingRows(count: 3, height: 180)
                else if (entries.isEmpty)
                  const EmptyStateCard(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Nothing here yet',
                    message: 'New features and fixes will show here.',
                  )
                else ...[
                  for (final entry in entries)
                    Container(
                      key: ValueKey('whatsNew-${entry.id}'),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                      decoration: BoxDecoration(
                        color: HuntrColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: HuntrColors.border),
                      ),
                      child: _EntryContent(
                          entry: entry, backendUrl: _backendUrl ?? ''),
                    ),
                  if (_next != null)
                    LoadMoreRow(onVisible: () => _load(more: true)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
