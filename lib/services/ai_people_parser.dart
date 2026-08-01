import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/ai_card_parser.dart';
import 'package:shadchan/services/ai_client.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/ai_config.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/parsed_person.dart';

/// Reads a table or a long message into many people at once.
///
/// The single-card path in [AiCardParser] fills a form the user is already
/// looking at, so a mistake there is visible. This one feeds a bulk import,
/// where records the user never opens can reach the database — so it asks the
/// model for one extra thing the single-card path does not need: whether a
/// gender was *stated* or *worked out*. That answer is what [ParsedPerson]
/// turns into a review decision.
abstract final class AiPeopleParser {
  static bool get isAvailable => FirebaseBootstrap.isReady;

  /// The religious styles the app itself knows, offered to the model by name.
  ///
  /// Taken from [ReligiousLevel] rather than written out again, so a style
  /// added to the app is immediately one the import can recognise instead of
  /// silently landing in `religiousLevelOther` forever.
  static final Map<String, ReligiousLevel> _religiousLevels =
      <String, ReligiousLevel>{
        for (final ReligiousLevel level in ReligiousLevel.values)
          if (level != ReligiousLevel.other) level.name: level,
      };

  static Iterable<String> get religiousLevelKeys => _religiousLevels.keys;

  /// Rows per request.
  ///
  /// Not a token limit — a correctness one. A long answer is where the model
  /// starts trimming, and a batch that quietly returns forty people for sixty
  /// rows is the failure that looks like success. Smaller batches also mean a
  /// single failure costs one chunk instead of the whole file.
  static const int rowsPerBatch = 25;

  /// Parses one chunk of text into people. Callers batch; this stays a single
  /// request so a failure is attributable to a known slice of the input.
  ///
  /// [mediaPaths] maps a file name in a WhatsApp export to where it was
  /// extracted on this device. When given, the model is asked which photo
  /// belongs to whom and the answer is resolved against this map — a name it
  /// invents resolves to nothing rather than to some other person's picture.
  static Future<List<ParsedPerson>> parseChunk(
    String text, {
    bool isChat = false,
    Map<String, String> mediaPaths = const <String, String>{},
    Map<int, String> messageTexts = const <int, String>{},
  }) async {
    if (text.trim().isEmpty) {
      throw const AiParseException(AiParseFailure.empty);
    }

    // Waited on here rather than checked, because Firebase now comes up lazily
    // and an import started from a share begins within a frame of the screen
    // opening — reading `isReady` at that moment says "no" and fails every
    // batch of a perfectly good file.
    await FirebaseBootstrap.ensureReady();
    if (!isAvailable) {
      throw AiParseException(
        AiParseFailure.unavailable,
        FirebaseBootstrap.failure,
      );
    }

    final GenerateContentResponse response;
    try {
      response =
          await AiClient.model(
                systemInstruction: Content.system(
                  isChat ? _chatInstruction : _systemInstruction,
                ),
                generationConfig: GenerationConfig(
                  responseMimeType: 'application/json',
                  responseSchema: _schema,
                  temperature: 0,
                  thinkingConfig: ThinkingConfig.withThinkingBudget(
                    AiConfig.thinkingBudget,
                  ),
                ),
              )
              .generateContent(<Content>[Content.text(text)])
              .timeout(AiConfig.requestTimeout);
    } catch (error) {
      throw classifyAiFailure(error);
    }

    return decodeResponse(
      response.text,
      mediaPaths: mediaPaths,
      messageTexts: messageTexts,
    );
  }

  /// Turns the model's array into people, dropping entries that carry nothing.
  ///
  /// A row that produced no usable field is not an error — spreadsheets are
  /// full of headers, totals and blank separators, and the model correctly
  /// reports them as having no person in them.
  @visibleForTesting
  static List<ParsedPerson> decodeResponse(
    String? raw, {
    Map<String, String> mediaPaths = const <String, String>{},
    Map<int, String> messageTexts = const <int, String>{},
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return const <ParsedPerson>[];
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <ParsedPerson>[];
    }

    final List<Object?> entries = switch (decoded) {
      final List<Object?> list => list,
      // A model asked for an array sometimes wraps it in an object anyway.
      final Map<String, dynamic> map when map['people'] is List<Object?> =>
        map['people'] as List<Object?>,
      _ => const <Object?>[],
    };

    final List<ParsedPerson> people = <ParsedPerson>[];
    for (final Object? entry in entries) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final ParsedPerson person = _decodePerson(
        entry,
        mediaPaths,
        messageTexts,
      );
      if (person.card.isNotEmpty) {
        people.add(person);
      }
    }
    return people;
  }

  static ParsedPerson _decodePerson(
    Map<String, dynamic> entry,
    Map<String, String> mediaPaths,
    Map<int, String> messageTexts,
  ) {
    // Reuses the single-card field reader so both paths share one set of
    // coercion and plausibility rules.
    final ParsedCard card = AiCardParser.cardFromJson(entry);

    // Only an explicit "stated" earns the fast path. A missing or unexpected
    // genderSource counts as inferred, because this flag is what lets a record
    // reach the database unseen — absence of a claim must not grant it.
    final Set<ParsedField> inferred = <ParsedField>{};
    if (card.gender != null && entry['genderSource'] != 'stated') {
      inferred.add(ParsedField.gender);
    }
    // Resolved against the files actually extracted from the export, so a
    // name the model invented attaches nothing rather than someone else's
    // photo.
    final Object? photoFile = entry['photoFile'];
    final String? photoPath = photoFile is String
        ? mediaPaths[photoFile.trim()]
        : null;

    // The card is lifted from the source by index rather than echoed back by
    // the model. A real card is paragraphs long; asking for it in the answer
    // costs output tokens on every person and invites paraphrase, and a
    // paraphrased card is a quiet rewrite of what someone said about
    // themselves.
    final Object? sourceMessage = entry['sourceMessage'];
    final String? description = sourceMessage is int
        ? messageTexts[sourceMessage]
        : null;

    final String? levelKey = entry['religiousLevel'] is String
        ? entry['religiousLevel'] as String
        : null;
    final String? levelOther = entry['religiousLevelOther'] is String
        ? (entry['religiousLevelOther'] as String).trim()
        : null;

    return ParsedPerson(
      card: card,
      inferredFields: inferred,
      photoPath: photoPath,
      religiousLevel: _religiousLevels[levelKey],
      // Only kept when it is actually saying something the list cannot.
      religiousLevelOther: _religiousLevels.containsKey(levelKey)
          ? null
          : (levelOther?.isEmpty ?? true)
          ? null
          : levelOther,
      phone: entry['phone'] is String ? entry['phone'] as String : null,
      description: (description?.trim().isEmpty ?? true)
          ? null
          : description!.trim(),
    );
  }

  static final Schema _schema = Schema.array(
    items: Schema.object(
      properties: <String, Schema>{
        'firstName': Schema.string(nullable: true),
        'lastName': Schema.string(nullable: true),
        'age': Schema.integer(nullable: true),
        'gender': Schema.enumString(
          enumValues: <String>['male', 'female'],
          nullable: true,
        ),
        'genderSource': Schema.enumString(
          enumValues: <String>['stated', 'inferred'],
          description:
              'stated when the row says the gender in words, inferred when it '
              'was worked out from the first name.',
          nullable: true,
        ),
        'city': Schema.string(nullable: true),
        'heightCm': Schema.integer(nullable: true),
        'maritalStatus': Schema.enumString(
          enumValues: <String>['single', 'divorced', 'widowed'],
          nullable: true,
        ),
        'religiousLevel': Schema.enumString(
          enumValues: <String>[...religiousLevelKeys],
          description:
              'The closest of these to what the text says. Null when it says '
              'nothing about religious style.',
          nullable: true,
        ),
        'religiousLevelOther': Schema.string(
          description:
              'The style in the text\'s own words, when none of the listed '
              'values fits it — for example "דתייה עם סימני שאלה".',
          nullable: true,
        ),
        'phone': Schema.string(
          description: 'The person\'s own phone number, not the sender\'s.',
          nullable: true,
        ),
        'sourceMessage': Schema.integer(
          description:
              'For a chat: the #number of the message holding this person\'s '
              'card, so it can be kept verbatim. Null if spread over several.',
          nullable: true,
        ),
        'inquiryContactName': Schema.string(nullable: true),
        'inquiryContactPhone': Schema.string(nullable: true),
        'photoFile': Schema.string(
          description:
              'The exact attached file name belonging to this person, copied '
              'from the transcript. Null when no photo clearly belongs to them.',
          nullable: true,
        ),
      },
    ),
  );

  static const String _systemInstruction = '''
You read a Hebrew shidduch (matchmaking) list into JSON — one object per
person. The input is tab-separated rows from a spreadsheet, or a long message
listing several people. Each line begins with its row number.

Return one object per person, in the order they appear. Skip anything that holds
no person: header rows, totals, section titles, notes and blank separators. Do
not invent a person to fill a cell, and do not merge two people into one.

A row is not necessarily one person. Work out the layout first:

- One person per row, with a column per field — the common case.
- A grid, where names are laid out across many columns and the *heading of the
  column a name sits in* gives it a value. A sheet whose first row reads
  21, 22, 23 … is stating each name's age by position: a name in the column
  headed 23 is 23 years old. Count tabs to find which column a name is in;
  empty cells are placeholders that hold the alignment, never people.
- A pairs table, with headings such as בן / בת — each row names *two* people,
  one per column. Return both. A status or note column describes the match
  between them, not either person, so it belongs to neither.

The first line of every batch is the sheet's header row, repeated so the column
meanings are available even when the batch starts further down. Do not return a
person for it.

- Extract every field a row states. Omit what it does not.
- gender: prefer gendered wording in the row (בן/בת, בחור/בחורה, רווק/רווקה) and
  set genderSource to "stated". Otherwise take it from the first name where
  Hebrew usage is unambiguous and set genderSource to "inferred". For a
  genuinely unisex name such as שי or אורי with no gendered wording, leave both
  gender and genderSource null. genderSource must never be "stated" unless a
  word in that row says the gender.
- maritalStatus: only from an explicit word — רווק/רווקה is single,
  גרוש/גרושה is divorced, אלמן/אלמנה is widowed. Never default to single.
- heightCm: whole centimetres. "1.78" and "178" are both 178.
- A person named as the contact for inquiries (לבירורים, להתקשר ל) belongs in
  inquiryContactName / inquiryContactPhone, never in firstName / lastName.
- religiousLevel: the closest listed value to what the text says. Read
  descriptions, not only labels — "רמה דתית: דתייה לאומית לכיוון לייט" is
  datiLite, "גדלתי בבית דתי ורואה את עצמי כדתייה" is datiLeumi. When the text
  says nothing about it, leave it null; when it says something no listed value
  covers, leave religiousLevel null and put the text's own words in
  religiousLevelOther.
- phone: the person's own number. A number belonging to whoever is passing the
  card along is inquiryContactPhone, never phone.
- Copy names, cities and phone numbers exactly as written. Do not translate,
  transliterate, correct spelling, or expand abbreviations.
''';

  /// The chat variant.
  ///
  /// A transcript is not a table: most of it is conversation, a card can be
  /// forwarded twice, and the same person can be mentioned for weeks. The
  /// extra work here is the photo — the model never sees an image, only a file
  /// name sitting between two messages, and has to decide from the
  /// conversation whether it belongs to the card before it or the one after.
  static const String _chatInstruction = '''
You read an exported Hebrew WhatsApp conversation and return the shidduch
candidates described in it — one object per person.

Each line is `#<number> <sender>: <message>`. A photo appears as
`[קובץ מצורף: <file name>]`.

Return a person only when the conversation actually describes one as a
candidate: a card, a profile, or a message giving their details. Ignore
ordinary conversation, questions, arrangements, and talk *about* a proposal
that gives no details. The same person forwarded or discussed more than once is
still one person — merge what the messages say about them rather than returning
them twice.

- photoFile: a photo usually arrives just before or just after the card it
  belongs to, but not always, and either order happens. Decide from the
  conversation who a photo is of, and copy the file name exactly as it appears.
  When no photo clearly belongs to a person, or you are choosing between two
  people for the same photo, leave it null — a picture attached to the wrong
  person is far worse than a person with no picture.
- The sender of a message is the matchmaker passing a card along, not the
  candidate. Never take the sender's name as the person's name unless the
  message says the card is about them.
- Extract every field the messages state. Omit what they do not.
- gender: prefer gendered wording (בן/בת, בחור/בחורה, רווק/רווקה) and set
  genderSource to "stated". Otherwise take it from the first name where Hebrew
  usage is unambiguous and set genderSource to "inferred". For a genuinely
  unisex name with no gendered wording, leave both null. genderSource must
  never be "stated" unless a word about that person says the gender.
- maritalStatus: only from an explicit word — רווק/רווקה is single,
  גרוש/גרושה is divorced, אלמן/אלמנה is widowed. Never default to single.
- heightCm: whole centimetres. "1.78" and "178" are both 178.
- A person named as the contact for inquiries (לבירורים, להתקשר ל) belongs in
  inquiryContactName / inquiryContactPhone, never in firstName / lastName.
- religiousLevel: the closest listed value to what the text says. Read
  descriptions, not only labels — "רמה דתית: דתייה לאומית לכיוון לייט" is
  datiLite, "גדלתי בבית דתי ורואה את עצמי כדתייה" is datiLeumi. When the text
  says nothing about it, leave it null; when it says something no listed value
  covers, leave religiousLevel null and put the text's own words in
  religiousLevelOther.
- phone: the person's own number. A number belonging to whoever is passing the
  card along is inquiryContactPhone, never phone.
- sourceMessage: the #number of the single message that holds this person's
  card. The card is kept word for word from that message, so point at the one
  describing them — not at a photo, and not at a reply about them. Leave it
  null when their details are spread over several messages.
- Copy names, cities and phone numbers exactly as written. Do not translate,
  transliterate, correct spelling, or expand abbreviations.
''';
}
