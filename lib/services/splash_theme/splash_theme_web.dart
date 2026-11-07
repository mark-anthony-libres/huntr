import 'package:web/web.dart' as web;

/// Read by index.html's first script (the same key).
const _key = 'huntr-splash-theme';

void save(
    {required String accent, required String ember, required String glow}) {
  try {
    web.window.localStorage
        .setItem(_key, '{"accent":"$accent","ember":"$ember","glow":"$glow"}');
  } catch (_) {
    // storage blocked (private mode): the page stays orange
  }
}
