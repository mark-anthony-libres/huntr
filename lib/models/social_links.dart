/// A network a profile can link to (like Grindr's social links).
enum SocialNetwork {
  instagram('Instagram', 'instagram_username', 'https://www.instagram.com/',
      asksForLink: true),
  x('X', 'x_username', 'https://x.com/'),
  facebook('Facebook', 'facebook_username', 'https://www.facebook.com/',
      asksForLink: true),
  tiktok('TikTok', 'tiktok_username', 'https://www.tiktok.com/@');

  const SocialNetwork(this.label, this.apiField, this._profileUrl,
      {this.asksForLink = false});
  final String label;

  /// What the backend calls it when saving.
  final String apiField;
  final String _profileUrl;

  /// Asked for as a pasted profile link (the backend keeps the username, or
  /// on Facebook the profile number); otherwise as a username.
  final bool asksForLink;

  /// Facebook profiles without a username have only a number
  /// (facebook.com/profile.php?id=61577660267848).
  bool _isNumber(String username) =>
      this == facebook && RegExp(r'^\d+$').hasMatch(username);

  /// Their profile on that network.
  Uri urlFor(String username) => _isNumber(username)
      ? Uri.parse('${_profileUrl}profile.php?id=$username')
      : Uri.parse('$_profileUrl$username');

  /// How it reads on a profile: "@name", or just the network's name for a
  /// Facebook profile number (no name to show).
  String shown(String username) => _isNumber(username) ? label : '@$username';
}

/// The usernames a profile shows, per network (unset ones aren't shown).
class SocialLinks {
  const SocialLinks([this.usernames = const {}]);

  /// From the backend's `social_links` ({"instagram": "name", "x": null, ...}).
  factory SocialLinks.fromJson(Object? json) {
    if (json is! Map) return const SocialLinks();
    return SocialLinks({
      for (final network in SocialNetwork.values)
        if (json[network.name] case final String name when name.isNotEmpty)
          network: name,
    });
  }

  final Map<SocialNetwork, String> usernames;

  bool get isEmpty => usernames.isEmpty;

  String? operator [](SocialNetwork network) => usernames[network];

  /// For saving: every network (an empty one clears it). What was typed is
  /// sent as it is; the backend cleans "@name" and pasted links.
  Map<String, String> toJson() => {
        for (final network in SocialNetwork.values)
          network.apiField: usernames[network] ?? '',
      };
}
