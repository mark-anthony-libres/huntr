import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../flows/chat_attachments.dart';
import '../services/feedback_service.dart';
import '../services/huntr_backend.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/block_gate.dart';
import '../widgets/profile/gradient_button.dart';

/// Send feedback (Settings > Support): a suggestion, a bug or anything else,
/// with an optional screenshot. Returns true once sent.
class SendFeedbackScreen extends StatefulWidget {
  const SendFeedbackScreen({super.key, required this.service});

  final FeedbackService service;

  @override
  State<SendFeedbackScreen> createState() => _SendFeedbackScreenState();
}

class _SendFeedbackScreenState extends State<SendFeedbackScreen> {
  final _message = TextEditingController();
  FeedbackType _type = FeedbackType.suggestion;
  Uint8List? _screenshot;
  String? _screenshotName;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final picked = await ChatMediaPicker.instance.pickImage();
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _screenshot = bytes;
      _screenshotName = picked.name;
    });
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (message.isEmpty || _sending || token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.service.send(token,
          type: _type,
          message: message,
          screenshot: _screenshot,
          screenshotName: _screenshotName);
      messenger.showSnackBar(
          const SnackBar(content: Text('Thanks! We read every message 🧡')));
      navigator.pop(true);
    } on SessionRejectedException {
      app.endSession();
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            "Your feedback didn't send. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = switch (_type) {
      FeedbackType.suggestion => 'What would make HUNTR better for you?',
      FeedbackType.bug =>
        'What happened, and what did you expect? Steps help us fix it fast.',
      FeedbackType.other => 'Tell us anything',
    };
    final canSend = _message.text.trim().isNotEmpty && !_sending;
    return Scaffold(
      appBar: AppBar(title: const Text('Send feedback')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const _Header(),
              const SizedBox(height: 28),
              const _Label('What is it about?'),
              const SizedBox(height: 10),
              Row(children: [
                for (final (i, type) in FeedbackType.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _TypeCard(
                      type: type,
                      selected: _type == type,
                      onTap: () => setState(() => _type = type),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 24),
              const _Label('Your message'),
              const SizedBox(height: 10),
              TextField(
                key: const Key('feedbackMessage'),
                controller: _message,
                minLines: 5,
                maxLines: 12,
                maxLength: FeedbackService.maxMessageLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(color: HuntrColors.muted),
                  hintMaxLines: 3,
                  contentPadding: const EdgeInsets.all(18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: HuntrColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        BorderSide(color: HuntrColors.orange, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _Label('Screenshot', optional: true),
              const SizedBox(height: 10),
              if (_screenshot case final shot?)
                _ScreenshotPreview(
                  bytes: shot,
                  name: _screenshotName,
                  onRemove: () => setState(() {
                    _screenshot = null;
                    _screenshotName = null;
                  }),
                )
              else
                _AddScreenshot(onTap: _pickScreenshot),
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: error),
              ],
              const SizedBox(height: 28),
              GradientButton(
                key: const Key('sendFeedback'),
                icon:
                    _sending ? Icons.hourglass_top_rounded : Icons.send_rounded,
                label: _sending ? 'Sending…' : 'Send feedback',
                onPressed: canSend ? _send : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'You can follow it in Settings › My feedback.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HuntrColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              gradient: HuntrColors.accentGradient, shape: BoxShape.circle),
          child: const Icon(Icons.favorite_rounded, color: Colors.black),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Help shape HUNTR',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 2),
            Text('Share an idea or report a problem. We read every message.',
                style: TextStyle(color: HuntrColors.muted)),
          ]),
        ),
      ]);
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.optional = false});

  final String text;
  final bool optional;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(
            text: text, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (optional)
          const TextSpan(
              text: '  optional',
              style: TextStyle(color: HuntrColors.muted, fontSize: 12)),
      ]));
}

/// Suggestion, Bug or Other: picked by tapping; orange when picked.
class _TypeCard extends StatelessWidget {
  const _TypeCard(
      {required this.type, required this.selected, required this.onTap});

  final FeedbackType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, about) = switch (type) {
      FeedbackType.suggestion => (Icons.lightbulb_outline_rounded, 'An idea'),
      FeedbackType.bug => (Icons.bug_report_outlined, 'Something broke'),
      FeedbackType.other => (
          Icons.chat_bubble_outline_rounded,
          'Anything else'
        ),
    };
    final color = selected ? HuntrColors.orange : HuntrColors.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? HuntrColors.orange.withValues(alpha: 0.12)
            : HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: selected ? HuntrColors.orange : HuntrColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          key: Key('feedbackType-${type.name}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(type.label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? HuntrColors.orange : null)),
              const SizedBox(height: 2),
              Text(about,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: HuntrColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AddScreenshot extends StatelessWidget {
  const _AddScreenshot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: HuntrColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: HuntrColors.border),
        ),
        child: InkWell(
          key: const Key('addScreenshot'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.add_photo_alternate_outlined,
                  color: HuntrColors.orange),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add a screenshot',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('Helps us see exactly what you mean',
                          style: TextStyle(
                              color: HuntrColors.muted, fontSize: 12)),
                    ]),
              ),
            ]),
          ),
        ),
      );
}

/// The picked screenshot as a thumbnail: tap to see it whole, ✕ to remove.
class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview(
      {required this.bytes, required this.name, required this.onRemove});

  final Uint8List bytes;
  final String? name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: HuntrColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(children: [
          GestureDetector(
            key: const Key('screenshotThumbnail'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                insetPadding: const EdgeInsets.all(12),
                child: InteractiveViewer(child: Image.memory(bytes)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  Image.memory(bytes, width: 64, height: 64, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name ?? 'Screenshot',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Text('Tap the picture to view it',
                  style: TextStyle(color: HuntrColors.muted, fontSize: 12)),
            ]),
          ),
          IconButton(
            key: const Key('removeScreenshot'),
            tooltip: 'Remove screenshot',
            icon: const Icon(Icons.close_rounded),
            onPressed: onRemove,
          ),
        ]),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('feedbackError'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuntrColors.coral.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuntrColors.coral.withValues(alpha: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, color: HuntrColors.coral),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ]),
      );
}

/// My feedback (Settings > Support): what I sent and where it stands.
class MyFeedbackScreen extends StatefulWidget {
  const MyFeedbackScreen({super.key, required this.service});

  final FeedbackService service;

  @override
  State<MyFeedbackScreen> createState() => _MyFeedbackScreenState();
}

class _MyFeedbackScreenState extends State<MyFeedbackScreen> {
  List<SentFeedback>? _sent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    final token = app.sessionToken;
    if (token == null) return;
    try {
      final sent = await widget.service.fetchMine(token);
      if (mounted) {
        setState(() {
          _sent = sent;
          _error = null;
        });
      }
    } on SessionRejectedException {
      app.endSession();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is BackendException
            ? e.message
            : "Your feedback couldn't load. Check your connection.");
      }
    }
  }

  Future<void> _sendNew() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SendFeedbackScreen(service: widget.service)));
    if (sent == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return Scaffold(
      appBar: AppBar(title: const Text('My feedback')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newFeedback'),
        onPressed: _sendNew,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Send feedback'),
      ),
      body: sent == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _load, child: const Text('Try again')),
                    ]),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: sent.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text("You haven't sent any feedback yet",
                            style: TextStyle(color: HuntrColors.muted)),
                      ),
                    ])
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                          itemCount: sent.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _FeedbackCard(
                            feedback: sent[i],
                            onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => FeedbackDetailScreen(
                                        feedback: sent[i]))),
                          ),
                        ),
                      ),
                    ),
            ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback, required this.onOpen});

  final SentFeedback feedback;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HuntrColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: HuntrColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('feedback-${feedback.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FeedbackMeta(feedback: feedback),
                    const SizedBox(height: 10),
                    Text(feedback.headline,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (feedback.message.trim() !=
                        feedback.headline.trim()) ...[
                      const SizedBox(height: 4),
                      Text(feedback.message,
                          style: const TextStyle(color: HuntrColors.muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (feedback.hasScreenshot ||
                        feedback.teamReply != null) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 14, children: [
                        if (feedback.teamReply != null)
                          _Note(
                              icon: Icons.mark_chat_unread_outlined,
                              text: 'The team replied',
                              color: HuntrColors.orange),
                        if (feedback.hasScreenshot)
                          const _Note(
                              icon: Icons.image_outlined,
                              text: 'Screenshot attached'),
                      ]),
                    ],
                  ]),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: HuntrColors.muted),
          ]),
        ),
      ),
    );
  }
}

/// Status, type and date, at the top of a card and of its details.
class _FeedbackMeta extends StatelessWidget {
  const _FeedbackMeta({required this.feedback});

  final SentFeedback feedback;

  @override
  Widget build(BuildContext context) => Row(children: [
        _StatusPill(status: feedback.status),
        if (feedback.typeLabel case final type?) ...[
          const SizedBox(width: 8),
          Text(type,
              style: const TextStyle(
                  color: HuntrColors.muted, fontWeight: FontWeight.w600)),
        ],
        const Spacer(),
        Text(formatBlockDate(feedback.sentAt),
            style: const TextStyle(color: HuntrColors.muted, fontSize: 12)),
      ]);
}

class _Note extends StatelessWidget {
  const _Note(
      {required this.icon, required this.text, this.color = HuntrColors.muted});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ]);
}

/// One piece of feedback: all of it, its screenshot, and the team's reply.
class FeedbackDetailScreen extends StatelessWidget {
  const FeedbackDetailScreen({super.key, required this.feedback});

  final SentFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              feedback.reference.isEmpty ? 'Feedback' : feedback.reference)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _FeedbackMeta(feedback: feedback),
              const SizedBox(height: 16),
              SelectableText(feedback.message,
                  style: const TextStyle(fontSize: 16, height: 1.4)),
              if (feedback.teamReply case final reply?) ...[
                const SizedBox(height: 24),
                Container(
                  key: const Key('feedbackTeamReply'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HuntrColors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: HuntrColors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('From the HUNTR team',
                            style: TextStyle(
                                color: HuntrColors.orange,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        SelectableText(reply),
                      ]),
                ),
              ],
              for (final url in feedback.screenshotUrls) ...[
                const SizedBox(height: 24),
                GestureDetector(
                  key: const Key('feedbackScreenshot'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                          child: Image.network(url,
                              webHtmlElementStrategy:
                                  WebHtmlElementStrategy.fallback)),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      // S3 links have no CORS headers: in a browser, show it
                      // as an <img> (like chat media)
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            "The screenshot couldn't load. Go back and open it again.",
                            style: TextStyle(color: HuntrColors.muted)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a piece of feedback stands, as the team set it.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Under Review' => HuntrColors.active,
      'More Info Required' => HuntrColors.orange,
      'Added to Roadmap' => HuntrColors.online,
      'Declined' => HuntrColors.coral,
      _ => HuntrColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
