// The phone and desktop apps are already apps: nothing to install.
bool isInstalled() => true;
bool canPrompt() => false;
bool isIos() => false;
Future<bool> prompt() async => false;
void onChange(void Function() listener) {}
bool dismissedRecently() => true;
void dismiss() {}
