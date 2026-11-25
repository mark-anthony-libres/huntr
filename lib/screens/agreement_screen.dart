import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

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

  /// Deletes the account. Throwing keeps the user here with the error.
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

  /// The sections list beside the text (wide enough for both).
  static const _sidebarWidth = 260.0;
  static const _sidebarGap = 20.0;

  /// Above a heading jumped to.
  static const _headingRoom = 16.0;

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

  /// The text's sections (its titles and numbered headings), in order, and
  /// a key on each heading (to find where it is).
  List<_Section> _sections = const [];
  List<GlobalKey> _headingKeys = const [];
  late _HeadingBuilder _headings = _HeadingBuilder(const []);

  /// Where each heading is (scroll offsets), measured once laid out.
  List<double>? _headingOffsets;

  /// The section being read (the last heading scrolled past).
  final _current = ValueNotifier<int>(0);

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
    _current.dispose();
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
      if (!mounted) return;
      final sections = _Section.parse(content);
      setState(() {
        _content = content;
        _sections = sections;
        _headingKeys = [for (final _ in sections) GlobalKey()];
        _headings = _HeadingBuilder(_headingKeys);
        _headingOffsets = null;
        _current.value = 0;
      });
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

  /// Declining deletes the account, so it's confirmed first.
  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline and delete your account?'),
        content: const Text(
            'Huntr can only be used if you accept the terms and privacy '
            'policy. Declining deletes your account and everything in it. '
            'You can sign up again any time.'),
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
    _follow(metrics.pixels);
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

  /// Where each heading is, as scroll offsets (once, after it's laid out).
  List<double>? _measureHeadings() {
    final known = _headingOffsets;
    if (known != null) return known;
    if (!_scroll.hasClients || _headingKeys.isEmpty) return null;
    final offsets = <double>[];
    for (final key in _headingKeys) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return null;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return null;
      offsets.add(viewport.getOffsetToReveal(box, 0).offset);
    }
    return _headingOffsets = offsets;
  }

  /// The section at [pixels]: the last heading at or above the top.
  void _follow(double pixels) {
    final offsets = _measureHeadings();
    if (offsets == null) return;
    var at = 0;
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] <= pixels + _headingRoom + 12) at = i;
    }
    // the very end: the last section, even if its heading never reaches the top
    if (_scroll.hasClients &&
        _scroll.position.extentAfter <= _endTolerance &&
        offsets.isNotEmpty) {
      at = offsets.length - 1;
    }
    _current.value = at;
  }

  /// To a section: its heading at the top.
  void _jumpTo(int index) {
    final offsets = _measureHeadings();
    if (offsets == null || index >= offsets.length) return;
    final position = _scroll.position;
    _scroll.animateTo(
      // a little room above the heading
      (offsets[index] - _headingRoom).clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    _current.value = index;
  }

  /// The sections in a sheet (phones: no room beside the text).
  void _openSections() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75),
        child: _SectionList(
          key: const Key('agreementSectionsSheet'),
          sections: _sections,
          current: _current,
          onOpen: (index) {
            Navigator.pop(sheetContext);
            _jumpTo(index);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asks = widget._asksForAcceptance;
    // wide: the sections beside the text; narrow: a Sections button above it
    final wide = MediaQuery.sizeOf(context).width >=
        _maxWidth + _sidebarWidth + _sidebarGap + 40;
    final hasSections = _content != null && _sections.length > 1;
    return Scaffold(
      appBar: asks
          ? null // new users can't leave; declining is the way out
          : AppBar(
              title: Text(switch (widget.document) {
              AgreementDocument.communityGuidelines => 'Community Guidelines',
              AgreementDocument.privacyPolicy => 'Privacy Policy',
              AgreementDocument.terms => 'Terms & guidelines',
            })),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: wide && hasSections
                    ? _maxWidth + _sidebarWidth + _sidebarGap
                    : _maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, asks ? 24 : 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (asks) ...[
                    const _Header(),
                    const SizedBox(height: 20),
                  ],
                  if (hasSections && !wide) ...[
                    _SectionsButton(
                        sections: _sections,
                        current: _current,
                        onPressed: _openSections),
                    const SizedBox(height: 10),
                  ],
                  Expanded(
                    child: wide && hasSections
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: _sidebarWidth,
                                child: _SectionList(
                                  key: const Key('agreementSections'),
                                  sections: _sections,
                                  current: _current,
                                  onOpen: _jumpTo,
                                ),
                              ),
                              const SizedBox(width: _sidebarGap),
                              Expanded(child: _documentCard()),
                            ],
                          )
                        : _documentCard(),
                  ),
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
            child: MarkdownBody(
                data: content,
                styleSheet: _style,
                // the headings carry keys (for the sections list)
                builders: {'h1': _headings, 'h2': _headings}),
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
                              style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()]),
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

/// One of the text's sections: a document's title (level 1) or a numbered
/// heading (level 2).
class _Section {
  const _Section(this.title, this.level);

  final String title;
  final int level;

  /// The `#` and `##` headings, in order (outside code blocks).
  static List<_Section> parse(String markdown) {
    final found = <_Section>[];
    var inCode = false;
    for (final line in markdown.split('\n')) {
      if (line.trimLeft().startsWith('```')) inCode = !inCode;
      if (inCode) continue;
      final match = RegExp(r'^(#{1,2})\s+(.+?)\s*#*\s*$').firstMatch(line);
      if (match == null) continue;
      final title = match.group(2)!.replaceAll(RegExp(r'[*_`]'), '').trim();
      found.add(_Section(title, match.group(1)!.length));
    }
    return found;
  }
}

/// Puts a key on each `#` and `##` heading, in order (the same order as
/// [_Section.parse]), drawn as the style sheet says.
class _HeadingBuilder extends MarkdownElementBuilder {
  _HeadingBuilder(this.keys);

  final List<GlobalKey> keys;
  int _next = 0;

  @override
  void visitElementBefore(md.Element element) {
    // a new build of the text starts from the first heading again
    if (element.tag == 'h1' && _next >= keys.length) _next = 0;
  }

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element,
      TextStyle? preferredStyle, TextStyle? parentStyle) {
    final key = _next < keys.length ? keys[_next] : null;
    _next++;
    return Text(element.textContent, key: key, style: preferredStyle);
  }
}

/// The sections, the one being read in the accent; tap one to go there.
/// Document titles group the numbered sections under them.
class _SectionList extends StatelessWidget {
  const _SectionList({
    super.key,
    required this.sections,
    required this.current,
    required this.onOpen,
  });

  final List<_Section> sections;
  final ValueListenable<int> current;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: current,
        builder: (context, at, _) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          itemCount: sections.length,
          itemBuilder: (context, i) {
            final section = sections[i];
            final here = i == at;
            final title = section.level == 1;
            return Padding(
              padding: EdgeInsets.only(top: title && i > 0 ? 14 : 0),
              child: Material(
                color: here
                    ? HuntrColors.orange.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: Key('agreementSection-$i'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onOpen(i),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Text(
                      section.title,
                      style: TextStyle(
                        fontSize: title ? 12.5 : 13.5,
                        height: 1.35,
                        letterSpacing: title ? 0.3 : 0,
                        fontWeight:
                            title || here ? FontWeight.w700 : FontWeight.w500,
                        color: here
                            ? HuntrColors.orange
                            : title
                                ? Colors.white
                                : HuntrColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

/// Phones: the section being read, tapped for all of them.
class _SectionsButton extends StatelessWidget {
  const _SectionsButton({
    required this.sections,
    required this.current,
    required this.onPressed,
  });

  final List<_Section> sections;
  final ValueListenable<int> current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF2C303A)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('agreementSectionsButton'),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(Icons.toc_rounded, size: 20, color: HuntrColors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: current,
                  builder: (context, at, _) => Text(
                    at < sections.length ? sections[at].title : 'Sections',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Sections',
                  style: TextStyle(
                      color: HuntrColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Icon(Icons.expand_more_rounded,
                  size: 20, color: HuntrColors.muted),
            ]),
          ),
        ),
      );
}
