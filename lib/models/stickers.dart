/// HUNTR's stickers, sent in chat; each one people have on someone counts on
/// their profile ("What others say about you"). Which stickers there are,
/// their names and pictures, all come from the server (run from the admin
/// dashboard): adding or changing one needs no new app.
class HuntrSticker {
  const HuntrSticker(
      {required this.id,
      required this.name,
      this.groupId,
      this.imageUrl,
      this.beansCost = 0});

  factory HuntrSticker.fromJson(Map<String, dynamic> json) => HuntrSticker(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Sticker',
        groupId: json['group_id'] as int?,
        imageUrl: json['image_url'] as String?,
        beansCost: json['beans_cost'] as int? ?? 0,
      );

  static List<HuntrSticker> listFromJson(Object? json) => [
        for (final item in json as List<dynamic>? ?? const [])
          HuntrSticker.fromJson(item as Map<String, dynamic>),
      ];

  final int id;
  final String name;
  final int? groupId;

  /// Its picture (a temporary link; null when it couldn't be made).
  final String? imageUrl;

  /// What sending it costs (0: free). The server charges it, from its own
  /// price, never this one.
  final int beansCost;
}

/// The chat's sticker picker, a page at a time: its groups (with the
/// stickers of this page), how many Beans I have (to show which stickers I
/// can afford; the server checks again on sending), and where the next page
/// starts.
class StickerCatalog {
  const StickerCatalog(
      {required this.groups, this.beansBalance = 0, this.nextOffset});

  factory StickerCatalog.fromJson(Map<String, dynamic> json) => StickerCatalog(
        groups: HuntrStickerGroup.listFromJson(json['groups']),
        beansBalance: json['beans_balance'] as int? ?? 0,
        nextOffset: json['next_offset'] as int?,
      );

  final List<HuntrStickerGroup> groups;
  final int beansBalance;

  /// Where the next page starts (null: this was the last).
  final int? nextOffset;

  /// This and the [next] page as one: a group that runs over both gets the
  /// next page's stickers after its own; the balance is the newer one.
  StickerCatalog followedBy(StickerCatalog next) {
    final merged = [...groups];
    for (final group in next.groups) {
      final i = merged.indexWhere((g) => g.id == group.id);
      if (i < 0) {
        merged.add(group);
      } else {
        final known = merged[i];
        merged[i] = HuntrStickerGroup(
          id: known.id,
          name: known.name,
          description: known.description,
          sortOrder: known.sortOrder,
          onePerGroupPerRecipient: known.onePerGroupPerRecipient,
          stickers: [...known.stickers, ...group.stickers],
        );
      }
    }
    return StickerCatalog(
        groups: merged,
        beansBalance: next.beansBalance,
        nextOffset: next.nextOffset);
  }
}

/// A number of Beans as people read it: 1,000.
String formatBeans(int beans) {
  final digits = beans.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '${beans < 0 ? '-' : ''}$grouped';
}

/// A section of the chat's sticker picker, with its stickers in order (as
/// the server has them: groups and their order are run from the admin
/// dashboard).
class HuntrStickerGroup {
  const HuntrStickerGroup({
    required this.id,
    required this.name,
    required this.stickers,
    this.description,
    this.sortOrder = 0,
    this.onePerGroupPerRecipient = false,
  });

  factory HuntrStickerGroup.fromJson(Map<String, dynamic> json) =>
      HuntrStickerGroup(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Stickers',
        description: json['description'] as String?,
        sortOrder: json['sort_order'] as int? ?? 0,
        onePerGroupPerRecipient:
            json['one_per_group_per_recipient'] as bool? ?? false,
        stickers: HuntrSticker.listFromJson(json['stickers']),
      );

  static List<HuntrStickerGroup> listFromJson(Object? json) => [
        for (final item in json as List<dynamic>? ?? const [])
          HuntrStickerGroup.fromJson(item as Map<String, dynamic>),
      ];

  final int id;
  final String name;

  /// A line under its name (e.g. "Show someone some love"), if it has one.
  final String? description;
  final int sortOrder;

  /// Only one active sticker from this group per sender and recipient: once
  /// one is sent to someone, another needs the first undone (the server
  /// checks; the picker says so up front).
  final bool onePerGroupPerRecipient;
  final List<HuntrSticker> stickers;
}

/// One kind of sticker on someone's profile: how many people sent it (never
/// who).
class StickerCount {
  const StickerCount(
      {required this.id,
      required this.name,
      required this.count,
      this.imageUrl});

  factory StickerCount.fromJson(Map<String, dynamic> json) => StickerCount(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Sticker',
        imageUrl: json['image_url'] as String?,
        count: json['count'] as int,
      );

  static List<StickerCount> listFromJson(Object? json) => [
        for (final item in json as List<dynamic>? ?? const [])
          StickerCount.fromJson(item as Map<String, dynamic>),
      ];

  final int id;
  final String name;
  final String? imageUrl;
  final int count;
}
