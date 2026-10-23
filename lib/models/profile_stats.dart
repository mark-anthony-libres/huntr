import 'models.dart' show SexualPosition;

/// One choice from a fixed list, as the backend names it.
abstract interface class StatChoice {
  String get label;
  String get apiName;
}

T? _parse<T extends StatChoice>(List<T> values, Object? apiName) {
  for (final v in values) {
    if (v.apiName == apiName) return v;
  }
  return null;
}

enum BodyType implements StatChoice {
  toned('Toned', 'toned'),
  average('Average', 'average'),
  large('Large', 'large'),
  muscular('Muscular', 'muscular'),
  slim('Slim', 'slim'),
  stocky('Stocky', 'stocky');

  const BodyType(this.label, this.apiName);
  @override
  final String label;
  @override
  final String apiName;
}

enum Ethnicity implements StatChoice {
  asian('Asian', 'asian'),
  black('Black', 'black'),
  latino('Latino', 'latino'),
  middleEastern('Middle Eastern', 'middle_eastern'),
  mixed('Mixed', 'mixed'),
  nativeAmerican('Native American', 'native_american'),
  white('White', 'white'),
  southAsian('South Asian', 'south_asian'),
  other('Other', 'other');

  const Ethnicity(this.label, this.apiName);
  @override
  final String label;
  @override
  final String apiName;
}

enum RelationshipStatus implements StatChoice {
  single('Single', 'single'),
  dating('Dating', 'dating'),
  exclusive('Exclusive', 'exclusive'),
  committed('Committed', 'committed'),
  partnered('Partnered', 'partnered'),
  engaged('Engaged', 'engaged'),
  married('Married', 'married'),
  openRelationship('Open relationship', 'open_relationship');

  const RelationshipStatus(this.label, this.apiName);
  @override
  final String label;
  @override
  final String apiName;
}

enum Tribe implements StatChoice {
  bear('Bear', 'bear'),
  cleanCut('Clean-Cut', 'clean_cut'),
  daddy('Daddy', 'daddy'),
  discreet('Discreet', 'discreet'),
  geek('Geek', 'geek'),
  jock('Jock', 'jock'),
  leather('Leather', 'leather'),
  otter('Otter', 'otter'),
  rugged('Rugged', 'rugged'),
  sober('Sober', 'sober'),
  trans('Trans', 'trans'),
  twink('Twink', 'twink');

  const Tribe(this.label, this.apiName);
  @override
  final String label;
  @override
  final String apiName;
}

/// How heights and weights are shown to me (they're stored in cm / kg).
enum MeasurementUnits {
  metric('cm / kg', 'metric'),
  imperial('ft / lb', 'imperial');

  const MeasurementUnits(this.label, this.apiName);
  final String label;
  final String apiName;

  static MeasurementUnits parse(Object? apiName) =>
      apiName == 'imperial' ? imperial : metric;

  String height(int cm) {
    if (this == metric) return '$cm cm';
    final inches = (cm / 2.54).round();
    return '${inches ~/ 12}\'${inches % 12}"';
  }

  String weight(int kg) =>
      this == metric ? '$kg kg' : '${(kg * 2.20462).round()} lb';
}

/// A profile's stats. Each null (or no tribes) isn't shown.
class ProfileStats {
  const ProfileStats({
    this.showAge = true,
    this.heightCm,
    this.weightKg,
    this.bodyType,
    this.sexualPosition,
    this.ethnicity,
    this.relationshipStatus,
    this.tribes = const {},
    this.units = MeasurementUnits.metric,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
        showAge: json['show_age'] as bool? ?? true,
        heightCm: json['height_cm'] as int?,
        weightKg: json['weight_kg'] as int?,
        bodyType: _parse(BodyType.values, json['body_type']),
        sexualPosition:
            SexualPosition.parse(json['sexual_position'] as String?),
        ethnicity: _parse(Ethnicity.values, json['ethnicity']),
        relationshipStatus:
            _parse(RelationshipStatus.values, json['relationship_status']),
        tribes: {
          for (final t in json['tribes'] as List<dynamic>? ?? const [])
            if (_parse(Tribe.values, t) case final tribe?) tribe,
        },
        units: MeasurementUnits.parse(json['measurement_units']),
      );

  /// Others see my age (Show Age).
  final bool showAge;
  final int? heightCm;
  final int? weightKg;
  final BodyType? bodyType;
  final SexualPosition? sexualPosition;
  final Ethnicity? ethnicity;
  final RelationshipStatus? relationshipStatus;
  final Set<Tribe> tribes;

  /// How I see heights and weights (mine and everyone's).
  final MeasurementUnits units;

  /// What PUT /profile/me takes.
  Map<String, dynamic> toJson() => {
        'show_age': showAge,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'body_type': bodyType?.apiName,
        'sexual_position': sexualPosition?.apiName,
        'ethnicity': ethnicity?.apiName,
        'relationship_status': relationshipStatus?.apiName,
        'tribes': [for (final t in tribes) t.apiName],
        'measurement_units': units.apiName,
      };

  /// The stats that are set, as (label, value) lines, in [units].
  List<(String, String)> lines(MeasurementUnits units) => [
        if (heightCm != null) ('Height', units.height(heightCm!)),
        if (weightKg != null) ('Weight', units.weight(weightKg!)),
        if (bodyType != null) ('Body Type', bodyType!.label),
        if (sexualPosition != null) ('Position', sexualPosition!.label),
        if (ethnicity != null) ('Ethnicity', ethnicity!.label),
        if (relationshipStatus != null)
          ('Relationship Status', relationshipStatus!.label),
        if (tribes.isNotEmpty)
          ('Tribes', [for (final t in tribes) t.label].join(', ')),
      ];

  ProfileStats copyWith({
    bool? showAge,
    MeasurementUnits? units,
    Set<Tribe>? tribes,
  }) =>
      ProfileStats(
        showAge: showAge ?? this.showAge,
        heightCm: heightCm,
        weightKg: weightKg,
        bodyType: bodyType,
        sexualPosition: sexualPosition,
        ethnicity: ethnicity,
        relationshipStatus: relationshipStatus,
        tribes: tribes ?? this.tribes,
        units: units ?? this.units,
      );

  /// One stat changed ("Do not show" clears it).
  ProfileStats withHeight(int? cm) => _with(heightCm: () => cm);
  ProfileStats withWeight(int? kg) => _with(weightKg: () => kg);
  ProfileStats withBodyType(BodyType? v) => _with(bodyType: () => v);
  ProfileStats withPosition(SexualPosition? v) =>
      _with(sexualPosition: () => v);
  ProfileStats withEthnicity(Ethnicity? v) => _with(ethnicity: () => v);
  ProfileStats withRelationship(RelationshipStatus? v) =>
      _with(relationshipStatus: () => v);

  ProfileStats _with({
    int? Function()? heightCm,
    int? Function()? weightKg,
    BodyType? Function()? bodyType,
    SexualPosition? Function()? sexualPosition,
    Ethnicity? Function()? ethnicity,
    RelationshipStatus? Function()? relationshipStatus,
  }) =>
      ProfileStats(
        showAge: showAge,
        heightCm: heightCm == null ? this.heightCm : heightCm(),
        weightKg: weightKg == null ? this.weightKg : weightKg(),
        bodyType: bodyType == null ? this.bodyType : bodyType(),
        sexualPosition:
            sexualPosition == null ? this.sexualPosition : sexualPosition(),
        ethnicity: ethnicity == null ? this.ethnicity : ethnicity(),
        relationshipStatus: relationshipStatus == null
            ? this.relationshipStatus
            : relationshipStatus(),
        tribes: tribes,
        units: units,
      );
}
