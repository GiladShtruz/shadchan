import 'package:flutter_test/flutter_test.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/services/ai_chat_command.dart';
import 'package:shadchan/utils/chat_idea_command.dart';
import 'package:shadchan/utils/enums.dart';

Person _p(String id, String first, String last) => Person(
  id: id,
  firstName: first,
  lastName: last,
  gender: Gender.female,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// "פתח רעיון בין יעל כהן לאורי לוי" — read locally, resolved against real
/// cards, and only a request when it reads as one.
void main() {
  test('a request to open an idea is told apart from a message', () {
    expect(
      ChatIdeaCommand.looksLike('פתח רעיון בין יעל כהן לאורי לוי'),
      isTrue,
    );
    expect(ChatIdeaCommand.looksLike('תפתחי רעיון: שירה ודני'), isTrue);
    expect(ChatIdeaCommand.looksLike('היה רעיון טוב, תודה!'), isFalse);
    expect(ChatIdeaCommand.looksLike('מה שלומך?'), isFalse);
  });

  test('the two names, with the Hebrew prefix letter taken off', () {
    final List<NamePair> pairs = ChatIdeaCommand.parse(
      'פתח רעיון בין יעל כהן לאורי לוי',
    );
    expect(pairs, contains(('יעל כהן', 'אורי לוי')));
    expect(
      ChatIdeaCommand.parse('פתח רעיון בין יעל כהן ואורי לוי'),
      contains(('יעל כהן', 'אורי לוי')),
    );
    expect(
      ChatIdeaCommand.parse('פתח רעיון בין יעל כהן עם אורי לוי'),
      contains(('יעל כהן', 'אורי לוי')),
    );
    // A name that starts with ל is offered both ways; resolution decides.
    expect(
      ChatIdeaCommand.parse('פתח רעיון בין שירה ללאה כהן'),
      contains(('שירה', 'לאה כהן')),
    );
  });

  test('names resolve to cards: full name first, then a first name', () {
    final List<Person> people = <Person>[
      _p('1', 'יעל', 'כהן'),
      _p('2', 'יעל', 'לוי'),
      _p('3', 'אורי', 'לוי'),
    ];
    expect(
      ChatIdeaCommand.resolve('יעל כהן', people).map((Person p) => p.id),
      <String>['1'],
    );
    // Two cards answer — the chat asks which.
    expect(ChatIdeaCommand.resolve('יעל', people), hasLength(2));
    expect(ChatIdeaCommand.resolve('דנה', people), isEmpty);
  });

  test("the model's answer counts only when it said yes and named two", () {
    expect(
      AiChatCommand.decode(
        '{"isIdeaRequest":true,"firstPerson":"יעל","secondPerson":"אורי"}',
      ),
      ('יעל', 'אורי'),
    );
    expect(
      AiChatCommand.decode(
        '{"isIdeaRequest":false,"firstPerson":null,"secondPerson":null}',
      ),
      isNull,
    );
    expect(AiChatCommand.decode('not json'), isNull);
    expect(
      AiChatCommand.decode('{"isIdeaRequest":true,"firstPerson":"יעל"}'),
      isNull,
    );
  });
}
