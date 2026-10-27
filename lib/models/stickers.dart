/// HUNTR's stickers, sent in chat; each one people have on someone counts on
/// their profile ("The word on you"). The same ids and order as the
/// backend's (sticker_submission_entity.STICKERS), which checks every send.
class HuntrSticker {
  const HuntrSticker(this.id, this.name);

  final String id;
  final String name;

  String get asset => stickerAsset(id);

  static const all = [
    HuntrSticker('pogi', 'Pogi'),
    HuntrSticker('big', 'Big'),
    HuntrSticker('good_sucker', 'Good sucker'),
    HuntrSticker('ulol', 'Ulol'),
    HuntrSticker('bad_side', 'Bad side'),
    HuntrSticker('small', 'Small'),
    HuntrSticker('smelly', 'Smelly'),
    HuntrSticker('yuck', 'Yuck'),
    HuntrSticker('eww', 'Eww'),
  ];

  static HuntrSticker? byId(String? id) =>
      all.where((sticker) => sticker.id == id).firstOrNull;
}

/// The picture for a sticker id (bundled with the app).
String stickerAsset(String id) => 'assets/stickers/$id.webp';

/// One kind of sticker on someone's profile: how many people sent it (never
/// who).
class StickerCount {
  const StickerCount({required this.id, required this.name, required this.count});

  factory StickerCount.fromJson(Map<String, dynamic> json) => StickerCount(
        id: json['id'] as String,
        name: json['name'] as String,
        count: json['count'] as int,
      );

  static List<StickerCount> listFromJson(Object? json) => [
        for (final item in json as List<dynamic>? ?? const [])
          StickerCount.fromJson(item as Map<String, dynamic>),
      ];

  final String id;
  final String name;
  final int count;

  String get asset => stickerAsset(id);
}
