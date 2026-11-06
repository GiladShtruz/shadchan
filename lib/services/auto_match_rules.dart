import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/utils/enums.dart';

/// One age band of the automatic filter: for a man whose age is in the band,
/// the women offered are at most [younger] years younger and at most [older]
/// years older than he is.
class AgeBand {
  const AgeBand({required this.younger, required this.older});

  final int younger;
  final int older;

  AgeBand copyWith({int? younger, int? older}) =>
      AgeBand(younger: younger ?? this.younger, older: older ?? this.older);

  @override
  bool operator ==(Object other) =>
      other is AgeBand && other.younger == younger && other.older == older;

  @override
  int get hashCode => Object.hash(younger, older);
}

/// The three bands the age rule is written in, by the man's age.
enum AgeBandKind {
  upTo30('עד גיל 30'),
  from31To40('גיל 31–40'),
  over40('מעל גיל 40');

  const AgeBandKind(this.label);

  final String label;

  static AgeBandKind forMaleAge(int age) {
    if (age > 40) {
      return AgeBandKind.over40;
    }
    if (age > 30) {
      return AgeBandKind.from31To40;
    }
    return AgeBandKind.upTo30;
  }
}

/// **The automatic filter's own criteria, as the matchmaker set them** —
/// "סינון אוטומטי" in the settings.
///
/// The automatic filter (what התאמות opens on for a friend without a filter of
/// their own, and what the database's own ideas are built from) used to be two
/// rules written into the code: an age rule in three bands and a table of
/// which religious styles are matched with which. They are the matchmaker's
/// judgement about people, not the app's, so they are now theirs to change.
/// The defaults are exactly the old rules, and an account that never opens the
/// page behaves exactly as before.
///
/// A synced setting (`autoMatch.rules`): it belongs to the account and is the
/// same on every phone. A friend's own "מה אני מחפש/ת" still wins over it, and
/// a filter set by hand on one friend's matches wins over both.
class AutoMatchRules {
  const AutoMatchRules({required this.ages, required this.styles});

  /// The rule for each band, by the man's age.
  final Map<AgeBandKind, AgeBand> ages;

  /// For each style in [ReligiousLevels.global], the styles it is shown.
  final Map<ReligiousLevel, List<ReligiousLevel>> styles;

  static const String settingsKey = 'autoMatch.rules';

  static const Map<AgeBandKind, AgeBand> defaultAges = <AgeBandKind, AgeBand>{
    AgeBandKind.upTo30: AgeBand(younger: 5, older: 1),
    AgeBandKind.from31To40: AgeBand(younger: 7, older: 2),
    AgeBandKind.over40: AgeBand(younger: 12, older: 5),
  };

  /// The table as it was written before it could be changed.
  static const Map<ReligiousLevel, List<ReligiousLevel>> defaultStyles =
      <ReligiousLevel, List<ReligiousLevel>>{
        ReligiousLevel.hiloni: <ReligiousLevel>[
          ReligiousLevel.hiloni,
          ReligiousLevel.masorti,
          ReligiousLevel.datlashi,
        ],
        ReligiousLevel.masorti: <ReligiousLevel>[
          ReligiousLevel.masorti,
          ReligiousLevel.hiloni,
          ReligiousLevel.datlashi,
        ],
        ReligiousLevel.datlashi: <ReligiousLevel>[
          ReligiousLevel.datlashi,
          ReligiousLevel.hiloni,
          ReligiousLevel.masorti,
        ],
        ReligiousLevel.datiOpen: <ReligiousLevel>[
          ReligiousLevel.datiOpen,
          ReligiousLevel.datiLeumi,
        ],
        ReligiousLevel.datiLeumi: <ReligiousLevel>[
          ReligiousLevel.datiLeumi,
          ReligiousLevel.datiOpen,
          ReligiousLevel.datiLeumiTorani,
        ],
        ReligiousLevel.datiLeumiTorani: <ReligiousLevel>[
          ReligiousLevel.datiLeumiTorani,
          ReligiousLevel.datiLeumi,
          ReligiousLevel.chardal,
        ],
        ReligiousLevel.chardal: <ReligiousLevel>[ReligiousLevel.chardal],
        ReligiousLevel.haredi: <ReligiousLevel>[ReligiousLevel.haredi],
      };

  static const AutoMatchRules defaults = AutoMatchRules(
    ages: defaultAges,
    styles: defaultStyles,
  );

  /// The furthest a band may reach either way.
  static const int maxYears = 20;

  AgeBand band(AgeBandKind kind) => ages[kind] ?? defaultAges[kind]!;

  /// The women's ages a man of [maleAge] is offered.
  ({int minAge, int maxAge}) femaleRangeFor(int maleAge) {
    final AgeBand rule = band(AgeBandKind.forMaleAge(maleAge));
    return (minAge: maleAge - rule.younger, maxAge: maleAge + rule.older);
  }

  /// The styles [level] is offered — always including [level] itself. Null
  /// for a style outside the global list, which keeps its old rule.
  List<ReligiousLevel>? stylesFor(ReligiousLevel level) {
    if (!ReligiousLevels.global.contains(level)) {
      return null;
    }
    final List<ReligiousLevel> chosen =
        styles[level] ?? defaultStyles[level] ?? <ReligiousLevel>[level];
    return <ReligiousLevel>[
      level,
      ...ReligiousLevels.global.where(
        (ReligiousLevel other) => other != level && chosen.contains(other),
      ),
    ];
  }

  bool get isDefault => this == defaults;

  AutoMatchRules withBand(AgeBandKind kind, AgeBand value) => AutoMatchRules(
    ages: <AgeBandKind, AgeBand>{...ages, kind: value},
    styles: styles,
  );

  AutoMatchRules withStyles(ReligiousLevel level, List<ReligiousLevel> value) =>
      AutoMatchRules(
        ages: ages,
        styles: <ReligiousLevel, List<ReligiousLevel>>{...styles, level: value},
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'ages': <String, Object?>{
      for (final AgeBandKind kind in AgeBandKind.values)
        kind.name: <int>[band(kind).younger, band(kind).older],
    },
    'styles': <String, Object?>{
      for (final ReligiousLevel level in ReligiousLevels.global)
        level.name: stylesFor(
          level,
        )!.map((ReligiousLevel l) => l.name).toList(),
    },
  };

  /// Reads what [toJson] wrote; anything missing or malformed is the default
  /// for that part, never an error.
  static AutoMatchRules fromJson(Object? json) {
    if (json is! Map) {
      return defaults;
    }
    final Map<AgeBandKind, AgeBand> ages = <AgeBandKind, AgeBand>{
      ...defaultAges,
    };
    final Object? rawAges = json['ages'];
    if (rawAges is Map) {
      for (final AgeBandKind kind in AgeBandKind.values) {
        final Object? pair = rawAges[kind.name];
        if (pair is List && pair.length == 2 && pair.every((e) => e is num)) {
          ages[kind] = AgeBand(
            younger: (pair[0] as num).round().clamp(0, maxYears),
            older: (pair[1] as num).round().clamp(0, maxYears),
          );
        }
      }
    }
    final Map<ReligiousLevel, List<ReligiousLevel>> styles =
        <ReligiousLevel, List<ReligiousLevel>>{...defaultStyles};
    final Object? rawStyles = json['styles'];
    if (rawStyles is Map) {
      for (final ReligiousLevel level in ReligiousLevels.global) {
        final Object? names = rawStyles[level.name];
        if (names is List) {
          styles[level] = ReligiousLevels.global
              .where((ReligiousLevel l) => names.contains(l.name))
              .toList();
        }
      }
    }
    return AutoMatchRules(ages: ages, styles: styles);
  }

  @override
  bool operator ==(Object other) =>
      other is AutoMatchRules &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  // --- the stored copy -----------------------------------------------------

  static String? _pending;
  static String? _decodedFrom;
  static AutoMatchRules _decoded = defaults;

  /// See `LocalSettingCaches.forgetAll`.
  static void forgetCache() {
    _pending = null;
    _decodedFrom = null;
    _decoded = defaults;
  }

  /// The rules in force. Read on every candidate the filter looks at, so the
  /// decoded copy is kept until the stored text changes.
  static AutoMatchRules get current {
    final Object? raw =
        _pending ??
        (Hive.isBoxOpen('settings')
            ? Hive.box<dynamic>('settings').get(settingsKey)
            : null);
    if (raw is! String || raw.isEmpty) {
      return defaults;
    }
    if (raw != _decodedFrom) {
      try {
        _decoded = fromJson(jsonDecode(raw));
      } on FormatException {
        _decoded = defaults;
      }
      _decodedFrom = raw;
    }
    return _decoded;
  }

  static void save(AutoMatchRules rules) {
    _pending = rules.isDefault ? '' : jsonEncode(rules.toJson());
    persistHomeSetting(settingsKey, _pending!);
  }

  static void reset() => save(defaults);
}
