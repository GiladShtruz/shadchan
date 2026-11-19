import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/models/idea_proposal.dart';
import 'package:shadchan/models/match_idea.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/match_repository.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/matchmaker_network.dart';
import 'package:shadchan/services/offline_guard.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:uuid/uuid.dart';

/// An idea shared with another matchmaker, from this side.
class SharedIdeaLink {
  const SharedIdeaLink({
    required this.proposalId,
    required this.matchId,
    required this.partnerUid,
    required this.partnerName,
    required this.theirPersonId,
    this.lastReported,
  });

  final String proposalId;

  /// The idea in this matchmaker's own "הרעיונות שלי".
  final String matchId;

  /// The matchmaker responsible for the other side.
  final String partnerUid;
  final String partnerName;

  /// The other side's friend, kept here outside the database (hidden) so the
  /// idea has two people — and its details survive a disconnect.
  final String theirPersonId;

  /// The status this side last told the partner.
  final String? lastReported;

  String get partnerFirstName {
    final String n = partnerName.trim();
    return n.isEmpty ? 'השדכן/ית' : n.split(RegExp(r'\s+')).first;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'proposalId': proposalId,
    'matchId': matchId,
    'partnerUid': partnerUid,
    'partnerName': partnerName,
    'theirPersonId': theirPersonId,
    'lastReported': lastReported,
  };

  static SharedIdeaLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? p = raw['proposalId'];
    final Object? m = raw['matchId'];
    final Object? u = raw['partnerUid'];
    final Object? t = raw['theirPersonId'];
    if (p is! String || m is! String || u is! String || t is! String) {
      return null;
    }
    return SharedIdeaLink(
      proposalId: p,
      matchId: m,
      partnerUid: u,
      partnerName: (raw['partnerName'] as String?) ?? '',
      theirPersonId: t,
      lastReported: raw['lastReported'] as String?,
    );
  }

  SharedIdeaLink reported(String status) => SharedIdeaLink(
    proposalId: proposalId,
    matchId: matchId,
    partnerUid: partnerUid,
    partnerName: partnerName,
    theirPersonId: theirPersonId,
    lastReported: status,
  );
}

/// **An idea two matchmakers share, each holding their own half.**
///
/// When an offered idea is approved, it opens in both "הרעיונות שלי": each
/// side's idea is their own friend and the other side's card, kept here
/// outside the database (a hidden record, never in "המאגר שלי" and never
/// offered onward). Each side moves their own idea as always; where it stands
/// is written to the proposal for the partner to see, and nothing else
/// crosses. The links are a synced setting, so every phone of the account
/// agrees which ideas are shared.
abstract final class SharedIdeas {
  static const String key = 'network.sharedIdeas';
  static const Uuid _uuid = Uuid();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Map<String, SharedIdeaLink>? _cache;

  /// Every link, by proposal id.
  static Map<String, SharedIdeaLink> get links {
    final Map<String, SharedIdeaLink>? cached = _cache;
    if (cached != null) return cached;
    final Map<String, SharedIdeaLink> out = <String, SharedIdeaLink>{};
    if (Hive.isBoxOpen('settings')) {
      final Object? raw = Hive.box<dynamic>('settings').get(key);
      if (raw is String && raw.isNotEmpty) {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final Object? v in decoded.values) {
              final SharedIdeaLink? link = SharedIdeaLink.fromJson(v);
              if (link != null) out[link.proposalId] = link;
            }
          }
        } catch (_) {}
      }
    }
    return _cache = out;
  }

  static void _save(Map<String, SharedIdeaLink> next) {
    _cache = next;
    persistHomeSetting(
      key,
      jsonEncode(<String, Object?>{
        for (final SharedIdeaLink l in next.values) l.proposalId: l.toJson(),
      }),
    );
    revision.value++;
  }

  static void forgetCache() {
    _cache = null;
    revision.value++;
  }

  /// The link of the idea [matchId], when it is shared.
  static SharedIdeaLink? forMatch(String matchId) {
    for (final SharedIdeaLink l in links.values) {
      if (l.matchId == matchId) return l;
    }
    return null;
  }

  /// Whether [personId] is another matchmaker's friend, kept for a shared
  /// idea — never to be offered onward.
  static bool isPartnersPerson(String personId) =>
      links.values.any((SharedIdeaLink l) => l.theirPersonId == personId);

  static bool _reconciling = false;

  /// Opens a local idea for every approved proposal this side has not opened
  /// yet. Automatic: it runs inside [OfflineGuard.exempt].
  static Future<void> reconcile({
    required List<IdeaProposal> proposals,
    required String me,
    required PersonRepository people,
    required MatchRepository matches,
  }) async {
    if (_reconciling) return;
    _reconciling = true;
    try {
      for (final IdeaProposal p in proposals) {
        if (p.status != IdeaProposalStatus.approved) continue;
        if (links.containsKey(p.id)) continue;
        final Person? mine = people.getById(p.myPersonIdFor(me));
        if (mine == null) continue;
        await OfflineGuard.exempt(() => _open(p, me, mine, people, matches));
      }
    } catch (error) {
      debugPrint('SharedIdeas: $error');
    } finally {
      _reconciling = false;
    }
  }

  static Future<void> _open(
    IdeaProposal p,
    String me,
    Person mine,
    PersonRepository people,
    MatchRepository matches,
  ) async {
    final Person shape = p.theirPersonFor(me);
    final DateTime now = DateTime.now();
    final String partnerName = p.otherNameOf(me);
    final Person theirs =
        Person(
            id: _uuid.v4(),
            firstName: shape.firstName,
            lastName: shape.lastName,
            gender: shape.gender,
            createdAt: now,
            updatedAt: now,
            hidden: true,
            source: 'רעיון משותף עם $partnerName',
          )
          ..birthDate = shape.birthDate
          ..religiousLevel = shape.religiousLevel
          ..religiousLevelOther = shape.religiousLevelOther
          ..city = shape.city
          ..description = shape.description
          ..heightCm = shape.heightCm
          ..maritalStatus = shape.maritalStatus
          ..region = shape.region
          ..preferredMinAge = shape.preferredMinAge
          ..preferredMaxAge = shape.preferredMaxAge
          ..preferredMinHeightCm = shape.preferredMinHeightCm
          ..preferredMaxHeightCm = shape.preferredMaxHeightCm
          ..preferredRegions = shape.preferredRegions
          ..preferredMaritalStatuses = shape.preferredMaritalStatuses
          ..preferredReligiousLevels = shape.preferredReligiousLevels
          ..preferredReligiousLevelOtherLabels =
              shape.preferredReligiousLevelOtherLabels
          ..tags = shape.tags
          ..profileStatus = shape.profileStatus;
    if (shape.birthDate == null) theirs.setManualAge(shape.age);

    // The other side's photos, copied into this account's own photos so the
    // idea keeps its faces after a disconnect.
    final List<String> photos = <String>[];
    final Directory dir = await PhotoPickerService.ensurePhotosDirectory();
    for (final String path in p.theirPhotoPathsFor(me)) {
      final File? fetched = await MatchmakerNetwork.photo(p.otherOf(me), path);
      if (fetched == null) continue;
      final String name = 'net_${p.id}_${PhotoPickerService.basenameOf(path)}';
      final File copy = await fetched.copy('${dir.path}/$name');
      photos.add(copy.path);
    }
    theirs.photosPaths = photos;
    await people.add(theirs);

    final bool iAmMale = mine.gender == Gender.male;
    final MatchIdea? idea = await matches.create(
      iAmMale ? mine.id : theirs.id,
      iAmMale ? theirs.id : mine.id,
    );
    if (idea == null) {
      await people.delete(theirs.id);
      return;
    }
    final String partnerFirst = partnerName.trim().isEmpty
        ? 'השדכן/ית'
        : partnerName.trim().split(RegExp(r'\s+')).first;
    await matches.addNote(
      idea.id,
      'רעיון משותף עם $partnerFirst · $partnerFirst אחראי/ת על ${theirs.firstName}',
      isAutomatic: true,
    );
    _save(<String, SharedIdeaLink>{
      ...links,
      p.id: SharedIdeaLink(
        proposalId: p.id,
        matchId: idea.id,
        partnerUid: p.otherOf(me),
        partnerName: partnerName,
        theirPersonId: theirs.id,
        lastReported: idea.status.name,
      ),
    });
    unawaited(MatchmakerNetwork.reportSide(p.id, idea.status.name));
  }

  /// Tells each partner where this side's half of a shared idea stands now.
  static void reportStatuses(MatchRepository matches) {
    final Map<String, SharedIdeaLink> current = links;
    Map<String, SharedIdeaLink>? next;
    for (final SharedIdeaLink link in current.values) {
      final MatchIdea? idea = matches.getById(link.matchId);
      if (idea == null) continue;
      final String status = idea.status.name;
      if (status == link.lastReported) continue;
      unawaited(MatchmakerNetwork.reportSide(link.proposalId, status));
      (next ??= <String, SharedIdeaLink>{...current})[link.proposalId] = link
          .reported(status);
    }
    if (next != null) _save(next);
  }
}
