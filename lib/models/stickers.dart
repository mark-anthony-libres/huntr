/// HUNTR's stickers, sent in chat; each one people have on someone counts on
/// their profile ("What others say about you"). Which stickers there are,
/// their names and pictures, all come from the server (run from the admin
/// dashboard): adding or changing one needs no new app.
class HuntrSticker {
  const HuntrSticker(
      {required this.id, required this.name, this.groupId, this.imageUrl});

  factory HuntrSticker.fromJson(Map<String, dynamic> json) => HuntrSticker(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Sticker',
        groupId: json['group_id'] as int?,
        imageUrl: json['image_url'] as String?,
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
}

/// A section of the chat's sticker picker, with its stickers in order (as
/// the server has them: groups and their order are run from the admin
/// dashboard).
class HuntrStickerGroup {
  const HuntrStickerGroup({
    required this.id,
    required this.name,
    required this.stickers,
    this.sortOrder = 0,
    this.onePerGroupPerRecipient = false,
  });

  factory HuntrStickerGroup.fromJson(Map<String, dynamic> json) =>
      HuntrStickerGroup(
        id: json['id'] as int,
        name: json['name'] as String? ?? 'Stickers',
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
