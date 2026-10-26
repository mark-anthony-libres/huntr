import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/agreement_service.dart';
import '../services/huntr_backend.dart';
import '../theme.dart';

/// Which document an [AgreementScreen] shows.
enum AgreementDocument { terms, communityGuidelines, privacyPolicy }

/// The terms, community guidelines or privacy policy, loaded from the
/// backend.
///
/// With [onAccept] and [onDecline] the user must choose (new users, before
/// onboarding): the terms and the privacy policy, one after the other.
/// Without them it's read-only (from the Me screen, or before signing in).
class AgreementScreen extends StatefulWidget {
  const AgreementScreen({
    super.key,
    required this.agreements,
    this.onAccept,
    this.onDecline,
  }) : document = AgreementDocument.terms;

  /// The Community Guidelines, read-only.
  const AgreementScreen.communityGuidelines(
      {super.key, required this.agreements})
      : document = AgreementDocument.communityGuidelines,
        onAccept = null,
        onDecline = null;

  /// The Privacy Policy, read-only.
  const AgreementScreen.privacyPolicy({super.key, required this.agreements})
      : document = AgreementDocument.privacyPolicy,
        onAccept = null,
        onDecline = null;

  final AgreementService agreements;

  final AgreementDocument document;
  final VoidCallback? onAccept;

  /// Deactivates the account. Throwing keeps the user here with the error.
  final Future<void> Function()? onDecline;

  bool get _asksForAcceptance => onAccept != null && onDecline != null;

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  /// How close to the bottom counts as having reached the end.
  static const _endTolerance = 24.0;

  /// Comfortable reading width on wide screens.
  static const _maxWidth = 720.0;

  static const _errorColor = Color(0xFFFF9B8A);

  String? _content;
  String? _error;

  /// "I agree" unlocks only after the user reached the end of the text.
  bool _readToEnd = false;

  /// How far through the text the user has scrolled, 0 to 1. Only the
  /// progress bar and the percentage listen: scrolling doesn't rebuild the
  /// screen (or re-lay out the document), which made it shake.
  final _progress = ValueNotifier<double>(0);

  final _scroll = ScrollController();

  /// Built once per theme: a new style sheet makes the Markdown rebuild.
  MarkdownStyleSheet? _style;

  bool _declining = false;
  String? _declineError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _style = _documentStyle(context);
  }

  @override
  void dispose() {
    _progress.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Down by most of a screen (a few lines stay in view to keep the place).
  void _scrollOnePage() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.animateTo(
      (position.pixels + position.viewportDimension * 0.85)
          .clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _load() async {
    setState(() {
      _content = null;
      _error = null;
      _readToEnd = false;
    });
    _progress.value = 0;
    try {
      final agreements = widget.agreements;
      final content = switch (widget.document) {
        AgreementDocument.communityGuidelines =>
          await agreements.fetchGuidelines(),
        AgreementDocument.privacyPolicy =>
          await agreements.fetchPrivacyPolicy(),
        // accepting covers the privacy policy too: it follows the terms
        AgreementDocument.terms when widget._asksForAcceptance =>
          (await Future.wait(
                  [agreements.fetch(), agreements.fetchPrivacyPolicy()]))
              .join('\n\n---\n\n'),
        AgreementDocument.terms => await agreements.fetch(),
      };
      if (mounted) setState(() => _content = content);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is BackendException
          ? error.message
          : switch (widget.document) {
              AgreementDocument.communityGuidelines =>
                'The Community Guidelines could not be loaded.',
              AgreementDocument.privacyPolicy =>
                'The Privacy Policy could not be loaded.',
              AgreementDocument.terms => 'The agreement could not be loaded.',
            });
    }
  }

  /// Declining deactivates the account, so it's confirmed first.
  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline and deactivate?'),
        content: const Text(
            'Huntr can only be used if you accept the terms and privacy '
            'policy. Declining '
            'deactivates your account and signs you out.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('agreementDeclineConfirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _declining = true;
      _declineError = null;
    });
    try {
      await widget.onDecline!();
    } catch (error) {
      if (!mounted) return;
      setState(() => _declineError = error is BackendException
          ? error.message
          : 'Declining failed. Please try again.');
    } finally {
      if (mounted) setState(() => _declining = false);
    }
  }

  void _onScrollMetrics(ScrollMetrics metrics) {
    final progress = metrics.maxScrollExtent <= 0
        ? 1.0
        : (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);
    final reachedEnd = metrics.extentAfter <= _endTolerance;
    _progress.value = progress;
    // the screen itself rebuilds once: when the end is first reached
    if (!reachedEnd || _readToEnd) return;
    void apply() {
      if (mounted && !_readToEnd) setState(() => _readToEnd = true);
    }

    // Metrics notifications can arrive during layout, where setState isn't
    // allowed; apply those right after the frame instead.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asks = widget._asksForAcceptance;
    return Scaffold(
      appBar: asks
          ? null // new users can't leave; declining is the way out
          : AppBar(
              title: Text(switch (widget.document) {
                AgreementDocument.communityGuidelines =>
                  'Community Guidelines',
                AgreementDocument.privacyPolicy => 'Privacy Policy',
                AgreementDocument.terms => 'Terms & guidelines',
              })),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, asks ? 24 : 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (asks) ...[
                    const _Header(),
                    const SizedBox(height: 20),
                  ],
                  Expanded(child: _documentCard()),
                  if (asks) ...[
                    const SizedBox(height: 16),
                    _actions(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _documentCard() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: HuntrColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C303A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Reading progress along the top edge of the card.
          if (_content != null)
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (context, progress, _) => LinearProgressIndicator(
                key: const Key('agreementProgress'),
                value: progress,
                minHeight: 3,
                backgroundColor: HuntrColors.surfaceHigh,
                valueColor: AlwaysStoppedAnimation(HuntrColors.orange),
              ),
            ),
          Expanded(child: _document()),
        ],
      ),
    );
  }

  Widget _document() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 36, color: HuntrColors.muted),
              const SizedBox(height: 12),
              Text(_error!,
                  key: const Key('agreementError'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HuntrColors.muted)),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('agreementRetry'),
                onPressed: _load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final content = _content;
    if (content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // Metrics notifications also arrive after the first layout, so text short
    // enough to fit counts as read without scrolling.
    return NotificationListener<Notification>(
      onNotification: (notification) {
        final metrics = switch (notification) {
          ScrollNotification(:final metrics) => metrics,
          ScrollMetricsNotification(:final metrics) => metrics,
          _ => null,
        };
        if (metrics != null) _onScrollMetrics(metrics);
        return false;
      },
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        radius: const Radius.circular(4),
        // Laid out whole, once (not lazily like Markdown's list): its full
        // height is known, so the scroll position, scrollbar and progress
        // don't jump as paragraphs come into view.
        child: SingleChildScrollView(
          key: const Key('agreementContent'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 20, 28, 28),
          child: RepaintBoundary(
            child: MarkdownBody(data: content, styleSheet: _style),
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet _documentStyle(BuildContext context) {
    const body = TextStyle(color: Color(0xFFD4D6DD), fontSize: 15, height: 1.6);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      listBullet: body,
      strong: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
      h1: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          height: 1.25,
          color: Colors.white),
      h1Padding: const EdgeInsets.only(bottom: 8),
      h2: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: HuntrColors.orange),
      h2Padding: const EdgeInsets.only(top: 22, bottom: 4),
      h3: const TextStyle(
          fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white),
      h3Padding: const EdgeInsets.only(top: 12),
      pPadding: const EdgeInsets.only(bottom: 4),
      blockSpacing: 10,
      listIndent: 22,
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2C303A))),
      ),
    );
  }

  Widget _actions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_content != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _readToEnd
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle,
                          size: 18, color: HuntrColors.online),
                      SizedBox(width: 6),
                      Text('Thanks for reading',
                          style: TextStyle(color: HuntrColors.muted)),
                    ],
                  )
                // tap: down a page
                : Center(
                    child: TextButton.icon(
                      key: const Key('agreementNextPage'),
                      onPressed: _scrollOnePage,
                      style: TextButton.styleFrom(
                        foregroundColor: HuntrColors.muted,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.keyboard_double_arrow_down,
                          size: 18),
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Scroll to the end to agree',
                            key: Key('agreementScrollHint')),
                        // a fixed width (and digits of one width), so the
                        // row stays still as the number changes
                        SizedBox(
                          width: 58,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _progress,
                            builder: (context, progress, _) => Text(
                              '  ·  ${(progress * 100).round()}%',
                              style: const TextStyle(fontFeatures: [
                                FontFeature.tabularFigures()
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
          ),
        if (_declineError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _declineError!,
              key: const Key('agreementDeclineError'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _errorColor),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('agreementDecline'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: HuntrColors.muted,
                  side: const BorderSide(color: Color(0xFF353944)),
                  shape: const StadiumBorder(),
                ),
                onPressed: _declining ? null : _decline,
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const Key('agreementAccept'),
                // Only once the user scrolled through the whole text.
                onPressed: _readToEnd && !_declining ? widget.onAccept : null,
                child: const Text('I agree'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Before you start" title for new users.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: HuntrColors.accentGradient,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified_user_outlined,
              color: Colors.black, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Before you start',
                  style: text.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              const Text(
                'Please read and accept our terms and privacy policy.',
                style: TextStyle(color: HuntrColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
