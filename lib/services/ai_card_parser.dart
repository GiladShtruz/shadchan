import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shadchan/services/ai_client.dart';
import 'package:shadchan/services/firebase_bootstrap.dart';
import 'package:shadchan/utils/ai_config.dart';
import 'package:shadchan/utils/card_parser.dart';
import 'package:shadchan/utils/enums.dart';

/// Why an AI parse could not be completed, in the terms the form needs to
/// explain it in Hebrew. The distinction matters: "no network" invites a retry,
/// "nothing found" does not.
enum AiParseFailure {
  unavailable,
  network,

  /// App Check refused to vouch for this install.
  ///
  /// Its own category because the fix is nothing like the others: retrying
  /// never helps, and on a debug build it almost always means the device's
  /// debug token is not on the allowlist. Reported as "unknown" it sent us
  /// looking at the parser instead of at the console.
  attestation,

  empty,
  unknown,
}

class AiParseException implements Exception {
  const AiParseException(this.reason, [this.cause]);

  final AiParseFailure reason;
  final Object? cause;

  @override
  String toString() => 'AiParseException($reason, $cause)';
}

/// Sorts a thrown error into the reason the UI needs.
///
/// App Check arrives as a `FirebaseException` from the `firebase_app_check`
/// plugin rather than as a `FirebaseAIException`, so without this it lands in
/// "unknown" — which is what sent us reading the parser when the answer was a
/// missing debug token. The follow-up failures say "Too many attempts",
/// because the SDK rate-limits itself after the first refusal; they are the
/// same condition and must not read as a different one.
AiParseException classifyAiFailure(Object error) {
  if (error is FirebaseException && error.plugin == 'firebase_app_check') {
    return AiParseException(AiParseFailure.attestation, error);
  }
  if (error is FirebaseAIException) {
    return AiParseException(AiParseFailure.network, error);
  }
  return AiParseException(AiParseFailure.unknown, error);
}

/// Reads a shidduch card with Gemini when [CardParser] cannot.
///
/// This is a fallback, never the first attempt. The local parser handles the
/// labelled cards that make up most of what arrives on WhatsApp — instantly,
/// offline, at no cost, and without a single personal detail leaving the phone.
/// Gemini is for the rest: the message written as a paragraph, the card with
/// its own idiosyncratic layout. Because a call costs money and sends the text
/// off the device, it only ever runs when the user asks for it explicitly.
///
/// Only the text the user just pasted is sent. Nothing is read out of the
/// existing database — no notes, no descriptions, no other people.
abstract final class AiCardParser {
  /// Whether the fallback can be offered at all. False on a device where
  /// Firebase never came up, so the form can hide the button instead of
  /// showing one that always fails.
  static bool get isAvailable => FirebaseBootstrap.isReady;

  static Future<ParsedCard> parse(String rawText) async {
    final String text = rawText.trim();
    if (text.isEmpty) {
      throw const AiParseException(AiParseFailure.empty);
    }
    // Awaited, not checked: Firebase comes up lazily, so a tap that lands
    // before it finishes would otherwise report the feature as unavailable.
    await FirebaseBootstrap.ensureReady();
    if (!isAvailable) {
      throw AiParseException(
        AiParseFailure.unavailable,
        FirebaseBootstrap.failure,
      );
    }

    final GenerateContentResponse response;
    try {
      response = await AiClient.model(
        systemInstruction: Content.system(_systemInstruction),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: _schema,
          // The task is extraction, not reasoning: a low temperature keeps the
          // model copying what the card says instead of composing a plausible
          // person around it, and thinking buys nothing for the same reason.
          temperature: 0,
          thinkingConfig: ThinkingConfig.withThinkingBudget(
            AiConfig.thinkingBudget,
          ),
        ),
      ).generateContent(<Content>[Content.text(text)]).timeout(AiConfig.requestTimeout);
    } catch (error) {
      throw classifyAiFailure(error);
    }

    final ParsedCard card = decodeResponse(response.text);
    if (card.isEmpty) {
      throw const AiParseException(AiParseFailure.empty);
    }
    return card;
  }

  /// Turns the model's JSON into a card, then hands it to [CardParser.sanitize]
  /// so it faces the same plausibility rules as a locally parsed one.
  ///
  /// A malformed or half-written response is treated as "found nothing" rather
  /// than an error — the user still has the local parse and the form in front
  /// of them, so there is nothing to recover from.
  @visibleForTesting
  static ParsedCard decodeResponse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const ParsedCard();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const ParsedCard();
    }
    if (decoded is! Map<String, dynamic>) {
      return const ParsedCard();
    }
    return cardFromJson(decoded);
  }

  /// Builds one card out of the model's field map.
  ///
  /// Shared with the bulk parser, which receives an array of these and must
  /// coerce and range-check each entry exactly as a single card is — an age of
  /// 300 or a height in metres cannot mean one thing alone and another in a
  /// batch of sixty.
  static ParsedCard cardFromJson(Map<String, dynamic> fields) {
    return CardParser.sanitize(
      ParsedCard(
        firstName: _readString(fields['firstName']),
        lastName: _readString(fields['lastName']),
        age: _readInt(fields['age']),
        gender: _readGender(_readString(fields['gender'])),
        city: _readString(fields['city']),
        heightCm: _readHeightCm(fields['heightCm']),
        maritalStatus: _readMaritalStatus(_readString(fields['maritalStatus'])),
        inquiryContactName: _readString(fields['inquiryContactName']),
        inquiryContactPhone: _readString(fields['inquiryContactPhone']),
      ),
    );
  }

  static String? _readString(Object? value) => value is String ? value : null;

  /// Accepts a number written either way — the schema asks for an integer, but
  /// a model that answers `"27"` should not cost the user the field.
  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  /// Reads a height before it becomes an `int`, because rounding first loses
  /// the answer.
  ///
  /// The schema asks for centimetres, but a model that replies `1.78` anyway
  /// would round to `2` through [_readInt], and 2 then reads as two metres —
  /// turning a 178cm person into a 200cm one. Applying the metres/centimetres
  /// rule to the raw value keeps both notations landing on 178.
  static int? _readHeightCm(Object? value) {
    final double? raw = switch (value) {
      final int number => number.toDouble(),
      final double number => number,
      final String text => double.tryParse(text.trim().replaceAll(',', '.')),
      _ => null,
    };
    if (raw == null) {
      return null;
    }
    return raw < 3 ? (raw * 100).round() : raw.round();
  }

  static Gender? _readGender(String? value) => switch (value) {
    'male' => Gender.male,
    'female' => Gender.female,
    _ => null,
  };

  static MaritalStatus? _readMaritalStatus(String? value) => switch (value) {
    'single' => MaritalStatus.single,
    'divorced' => MaritalStatus.divorced,
    'widowed' => MaritalStatus.widowed,
    _ => null,
  };

  /// Every field is required and nullable — deliberately not optional.
  ///
  /// With the fields optional the model was free to just stop writing, and it
  /// did: on gemini-3.5-flash-lite the same card parsed twice returned nine
  /// fields once and three the next time, at temperature 0. Requiring every key
  /// forces an explicit decision per field, so "not stated" has to be written
  /// as null instead of being indistinguishable from the model losing interest.
  /// Keep this even on a model that looks stable without it — the failure was
  /// silent, and it filled the form with less than the card actually said.
  static final Schema _schema = Schema.object(
    properties: <String, Schema>{
      'firstName': Schema.string(nullable: true),
      'lastName': Schema.string(nullable: true),
      'age': Schema.integer(nullable: true),
      'gender': Schema.enumString(
        enumValues: <String>['male', 'female'],
        nullable: true,
      ),
      'city': Schema.string(nullable: true),
      'heightCm': Schema.integer(
        description: 'Height in whole centimetres.',
        nullable: true,
      ),
      'maritalStatus': Schema.enumString(
        enumValues: <String>['single', 'divorced', 'widowed'],
        nullable: true,
      ),
      'inquiryContactName': Schema.string(nullable: true),
      'inquiryContactPhone': Schema.string(nullable: true),
    },
  );

  /// Tuned against real card shapes, and deliberately two-sided.
  ///
  /// An earlier version said only "never infer", and the model answered by
  /// dropping ages, cities and heights that the card stated plainly — while
  /// still volunteering a marital status nobody had written. So the rule is
  /// split: take everything stated, including bare values in a comma list, and
  /// withhold only the two fields it is actually tempted to invent.
  static const String _systemInstruction = '''
You extract details from a Hebrew shidduch (matchmaking) card into JSON.

Extract every field the card states, including values written bare in a list —
"שי לוי, 26, תל אביב" states a name, an age and a city, and all three must be
reported. Omit a field only when the card genuinely does not mention it.

- gender: from gendered wording (בן/בת, בחור/בחורה, רווק/רווקה, הוא/היא) when
  present, otherwise from the first name where it is unambiguous in Hebrew
  usage — נועה and שרה are female, דוד and אברהם are male. Leave it null only
  for a genuinely unisex name with no gendered wording anywhere, such as שי or
  אורי.
- maritalStatus: only from an explicit word — רווק/רווקה is single,
  גרוש/גרושה is divorced, אלמן/אלמנה is widowed. A card that says nothing about
  it has no marital status. Never default to single.
- age: a number labelled גיל, or following בן/בת, or standing alone beside the
  name.
- heightCm: whole centimetres. "1.78" and "178" are both 178.
- firstName / lastName are the subject of the card. Someone named only as the
  person to call for inquiries (לבירורים, להתקשר ל) goes in
  inquiryContactName / inquiryContactPhone, never in firstName / lastName.
- Copy names, cities and phone numbers exactly as written. Do not translate,
  transliterate, correct spelling, or expand abbreviations.
''';
}
