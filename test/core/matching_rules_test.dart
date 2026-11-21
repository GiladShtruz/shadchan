import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/card_sync_engine.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/match_suggestion_utils.dart';

Person _p(
  String id,
  Gender gender, {
  int? age,
  ReligiousLevel? style = ReligiousLevel.datiLeumi,
  List<String> tags = const <String>[],
  DateTime? updatedAt,
}) {
  final DateTime now = DateTime.now();
  return Person(
    id: id,
    firstName: id,
    lastName: '',
    gender: gender,
    manualAge: age,
    manualAgeUpdatedAt: age == null ? null : now,
    religiousLevel: style,
    tags: List<String>.of(tags),
    createdAt: updatedAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  final Person him = _p(
    'him',
    Gender.male,
    age: 28,
    tags: <String>['טבע', 'ספרים', 'מוזיקה', 'טיולים'],
  );

  test(
    'age and religious style are both required — tags never let anybody in',
    () {
      // Many shared tags, but far outside the age range.
      final Person older = _p(
        'older',
        Gender.female,
        age: 45,
        tags: <String>['טבע', 'ספרים', 'מוזיקה', 'טיולים'],
      );
      // Many shared tags, but a style he is not matched with.
      final Person otherStyle = _p(
        'haredi',
        Gender.female,
        age: 26,
        style: ReligiousLevel.haredi,
        tags: <String>['טבע', 'ספרים', 'מוזיקה'],
      );
      // Unknown age or style is never "fits".
      final Person noAge = _p('noAge', Gender.female, tags: <String>['טבע']);
      final Person noStyle = _p('noStyle', Gender.female, age: 26, style: null);
      final Person fits = _p('fits', Gender.female, age: 26);
      for (final Person out in <Person>[older, otherStyle, noAge, noStyle]) {
        expect(
          MatchSuggestionUtils.matchesBasicPreferences(
            source: him,
            candidate: out,
          ),
          isFalse,
          reason: out.id,
        );
      }
      expect(
        MatchSuggestionUtils.matchesBasicPreferences(
          source: him,
          candidate: fits,
        ),
        isTrue,
      );
    },
  );

  test('among those who fit, more shared tags come first', () {
    final DateTime old = DateTime(2026, 1, 1);
    final Person one = _p(
      'one',
      Gender.female,
      age: 26,
      tags: <String>['טבע'],
      updatedAt: DateTime(2026, 11, 20),
    );
    final Person four = _p(
      'four',
      Gender.female,
      age: 25,
      tags: <String>['טבע', 'ספרים', 'מוזיקה', 'טיולים'],
      updatedAt: old,
    );
    final Person none = _p(
      'none',
      Gender.female,
      age: 27,
      updatedAt: DateTime(2026, 11, 21),
    );
    final Person outside = _p(
      'outside',
      Gender.female,
      age: 50,
      tags: <String>['טבע', 'ספרים', 'מוזיקה', 'טיולים'],
    );
    final List<String> order = MatchSuggestionUtils.ranked(
      source: him,
      people: <Person>[none, one, outside, four],
    ).map((Person p) => p.id).toList();
    expect(order, <String>['four', 'one', 'none']);
  });

  test('the reason says what the match stands on, in words, never a score', () {
    final Person her = _p(
      'her',
      Gender.female,
      age: 26,
      tags: <String>['טבע', 'ספרים', 'מוזיקה'],
    );
    expect(MatchSuggestionUtils.reasons(source: him, candidate: her), <String>[
      'מתאים בטווח הגילאים',
      'סגנון דתי מתאים',
      '3 תגיות משותפות',
    ]);
    final Person plain = _p('plain', Gender.female, age: 26);
    expect(
      MatchSuggestionUtils.reasons(source: him, candidate: plain),
      <String>['מתאים בטווח הגילאים', 'סגנון דתי מתאים'],
    );
  });

  test('a change on either card changes the answer at once', () {
    final Person her = _p('her', Gender.female, age: 26);
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(source: him, candidate: her),
      isTrue,
    );
    her.religiousLevel = ReligiousLevel.haredi;
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(source: him, candidate: her),
      isFalse,
    );
    her
      ..religiousLevel = ReligiousLevel.datiLeumi
      ..manualAge = 45;
    expect(
      MatchSuggestionUtils.matchesBasicPreferences(source: him, candidate: her),
      isFalse,
    );
  });

  test('the single\'s own tags reach the matchmaker\'s copy, quietly', () {
    final DateTime created = DateTime(2026, 1, 1);
    final Person copy = _p(
      'copy',
      Gender.female,
      age: 26,
      tags: <String>['טבע', 'פרטי שלי'],
      updatedAt: created,
    )..cardOwnerUid = 'owner';
    final Map<String, Object?> before = <String, Object?>{
      'firstName': 'copy',
      'gender': 'female',
      'tags': <String>['טבע'],
    };
    final Map<String, dynamic> after = <String, dynamic>{
      'firstName': 'copy',
      'gender': 'female',
      'tags': <String>['ספרים', 'מוזיקה'],
    };
    final CardSyncResult result = CardSyncEngine.apply(
      copy,
      after,
      ownerUid: 'owner',
      localPhotoPaths: null,
      previousRemote: before,
    );
    expect(result.changed, isTrue);
    // What the owner removed went, what they added arrived, the matchmaker's
    // private tag stayed.
    expect(copy.tags, <String>['פרטי שלי', 'ספרים', 'מוזיקה']);
    // Sync is not activity: the record's dates do not move.
    expect(copy.createdAt, created);
    expect(copy.updatedAt, created);
  });
}
