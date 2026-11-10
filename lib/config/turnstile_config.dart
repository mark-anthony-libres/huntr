/// Cloudflare Turnstile, the bot check before a sign-in code is emailed.
/// The site key is public (the secret one is only on the backend).
class TurnstileConfig {
  const TurnstileConfig._();

  /// The "HUNTR email sign-in" widget in the Cloudflare dashboard.
  static const siteKey = '0x4AAAAAAF7Ufe6MfxRSP0Va';

  /// On Android and iOS the check runs in a web view that says it's this
  /// page: one of the widget's hostnames (huntr.online, web.huntr.online,
  /// localhost). On the web the page's own address is used.
  static const baseUrl = 'https://huntr.online/';
}
