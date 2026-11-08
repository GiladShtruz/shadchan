import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/services/analytics_service.dart';

/// The measurement layer's one promise: what was done, never about whom.
/// These tests hold that line whatever a future call site hands in.
void main() {
  test('only numbers, booleans and short ascii codes survive', () {
    final Map<String, Object> clean = Analytics.sanitize(<String, Object?>{
      'source': 'contacts',
      'friends_band': 'n10_24',
      'count': 12,
      'has_note': true,
      'name': 'דוד כהן', // a name
      'phone': '054-1234567', // a number
      'card': 'בן 25, דתי לאומי', // card text
      'person_id': '3f2a9c1e-77b0-4d1e-9d52-1a2b3c4d5e6f', // an id
      'Bad-Key': 'x', // a key that is not a code
      'empty': null,
    });

    expect(clean, <String, Object>{
      'source': 'contacts',
      'friends_band': 'n10_24',
      'count': 12,
      'has_note': 1,
    });
  });

  test('counts travel as bands', () {
    expect(Analytics.band(0), 'n0');
    expect(Analytics.band(3), 'n1_4');
    expect(Analytics.band(7), 'n5_9');
    expect(Analytics.band(12), 'n10_24');
    expect(Analytics.band(612), 'n500_plus');
  });

  test('an error is reported by its type, never its message', () {
    final String code = Analytics.errorCode(
      FormatException('could not read /data/user/0/דוד_כהן.jpg'),
    );
    expect(code, 'formatexception');
  });

  test('every catalogued event name is a console-safe code', () {
    for (final AnalyticsEvent event in AnalyticsEvent.values) {
      expect(
        RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(event.name),
        isTrue,
        reason: event.name,
      );
    }
  });

  test('a logged event goes through the same filter', () {
    final List<(String, Map<String, Object>)> sent =
        <(String, Map<String, Object>)>[];
    Analytics.debugSink = (String name, Map<String, Object> params) =>
        sent.add((name, params));
    addTearDown(() => Analytics.debugSink = null);

    Analytics.log(AnalyticsEvent.friend_added, <String, Object?>{
      'source': 'manual',
      'first_name': 'שרה',
    });

    expect(sent.single.$1, 'friend_added');
    expect(sent.single.$2, <String, Object>{'source': 'manual'});
  });
}
