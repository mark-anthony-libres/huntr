import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// What index.html keeps: the browser's install offer (window.huntrInstall).
JSObject? get _install => globalContext['huntrInstall'] as JSObject?;

const _dismissedKey = 'huntr-install-dismissed-until';
const _quietFor = Duration(days: 14);

bool isInstalled() {
  if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
  // iOS Safari's own flag for a home-screen app
  final ios = (web.window.navigator as JSObject)['standalone'];
  if (ios != null && ios.dartify() == true) return true;
  final kept = _install?['installed'];
  return kept != null && kept.dartify() == true;
}

bool canPrompt() {
  final event = _install?['prompt'];
  return event != null && !event.isUndefinedOrNull;
}

bool isIos() {
  final agent = web.window.navigator.userAgent;
  return RegExp('iPhone|iPad|iPod').hasMatch(agent) ||
      // iPadOS says it's a Mac; touch tells them apart
      (agent.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
}

Future<bool> prompt() async {
  final install = _install;
  final event = install?['prompt'] as JSObject?;
  if (install == null || event == null) return false;
  // the browser allows its dialog once per offer
  install['prompt'] = null;
  await (event.callMethod<JSPromise?>('prompt'.toJS))?.toDart;
  final choice = await (event['userChoice'] as JSPromise<JSObject>).toDart;
  return (choice['outcome'] as JSString?)?.toDart == 'accepted';
}

void onChange(void Function() listener) {
  globalContext['huntrInstallChanged'] = listener.toJS;
}

bool dismissedRecently() {
  try {
    final until =
        int.tryParse(web.window.localStorage.getItem(_dismissedKey) ?? '');
    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  } catch (_) {
    return false; // storage blocked: just show it
  }
}

void dismiss() {
  try {
    web.window.localStorage.setItem(_dismissedKey,
        '${DateTime.now().add(_quietFor).millisecondsSinceEpoch}');
  } catch (_) {
    // storage blocked: it comes back next time
  }
}
