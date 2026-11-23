/// A build for the App Store or Google Play (`--dart-define STORE_BUILD=true`,
/// env/store.json): both stores reject explicit media, so threads tagged NSFW
/// aren't shown, the NSFW tag can't be picked, and there's no setting or
/// onboarding step about them. The website and the self-installed Android
/// app (env/prod.json) are unchanged.
const isStoreBuild = bool.fromEnvironment('STORE_BUILD');
