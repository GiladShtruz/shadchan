import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shadchan/utils/community_links.dart';
import 'package:shadchan/widgets/card_text_field.dart';

/// The line every card carries out of the app.
///
/// It is the only marketing in the product and it rides on somebody's shidduch,
/// so the rules are narrow: it is always there, it is never there twice, and it
/// never turns an empty share into an advertisement on its own.
void main() {
  test('it names the app, says what it is, and links to it', () {
    expect(CommunityLinks.sharedCardCredit, contains('שדכן'));
    expect(CommunityLinks.sharedCardCredit, contains('יומן אישי לניהול הצעות'));
    expect(CommunityLinks.sharedCardCredit, contains('להורדה:'));
    expect(
      CommunityLinks.sharedCardCredit,
      contains(CommunityLinks.downloadUrl),
    );
  });

  test('a card keeps its own text and gains a footer', () {
    final String credited = CommunityLinks.creditCard('בן 24, ירושלים.');

    expect(credited, startsWith('בן 24, ירושלים.'));
    expect(credited, endsWith(CommunityLinks.sharedCardCredit));
    // A blank line between them, so it reads as a footer rather than as the
    // card's last sentence.
    expect(credited, contains('\n\n'));
  });

  test('a card that already carries it is left exactly as it is', () {
    // What comes back when somebody pastes a card they received into the app
    // and forwards it on again.
    final String once = CommunityLinks.creditCard('בן 24, ירושלים.');
    expect(CommunityLinks.creditCard(once), once);
  });

  test('surrounding whitespace is not carried into the share', () {
    expect(
      CommunityLinks.creditCard('  בן 24.  \n\n'),
      'בן 24.\n\n${CommunityLinks.sharedCardCredit}',
    );
  });

  test(
    'an empty card is the credit alone — for a card that is only photos',
    () {
      // The guard against sharing *nothing but* an advertisement lives in
      // `ShareUtils`, which refuses to share at all when there is neither text
      // nor a photo. Here a card with photos and no words is still a card.
      expect(CommunityLinks.creditCard('   '), CommunityLinks.sharedCardCredit);
    },
  );

  group('pasting a shared card back in', () {
    test('the credit and the link come off', () {
      final String shared = CommunityLinks.creditCard(
        'בן 24, ירושלים.\nדתי לאומי.',
      );
      expect(
        CommunityLinks.stripCredit(shared),
        'בן 24, ירושלים.\nדתי לאומי.',
      );
    });

    test('WhatsApp curly quotes and a bare link line are recognised', () {
      const String forwarded =
          'בת 23, מודיעין\n\nשותף מ”שדכן” - יומן אישי לניהול הצעות.\n'
          'https://shadchan-app-eosin.vercel.app';
      expect(CommunityLinks.stripCredit(forwarded), 'בת 23, מודיעין');
    });

    test('a card with no credit is left exactly as it is', () {
      const String card = 'בן 25, עובד בהייטק.  \nאוהב טיולים ';
      expect(CommunityLinks.stripCredit(card), card);
    });

    test('the formatter strips a pasted credit and leaves typing alone', () {
      const CardCreditFormatter formatter = CardCreditFormatter();
      final String pasted = CommunityLinks.creditCard('בן 24.');
      final TextEditingValue result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: pasted,
          selection: TextSelection.collapsed(offset: pasted.length),
        ),
      );
      expect(result.text, 'בן 24.');
      expect(result.selection.extentOffset, 'בן 24.'.length);

      const TextEditingValue typed = TextEditingValue(
        text: 'בן 24. ש',
        selection: TextSelection.collapsed(offset: 8),
      );
      expect(
        formatter.formatEditUpdate(
          const TextEditingValue(text: 'בן 24. '),
          typed,
        ),
        typed,
      );
    });
  });
}
