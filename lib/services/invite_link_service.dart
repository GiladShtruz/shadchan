import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:shadchan/services/home_board_store.dart';
import 'package:shadchan/services/sign_in_prompt_store.dart';
import 'package:shadchan/services/workspace_store.dart';

/// A matchmaker's invitation to write a personal card.
/// What opening an invitation link came to.
enum InviteArrival {
  none,

  /// A brand-new install: the card owner's route was chosen for them.
  freshInstall,

  /// Somebody already signed in opened the link — a friend's invitation or an
  /// access request, both of which are answered in the personal area.
  signedIn,
}

class PendingInvite {
  const PendingInvite({required this.fromUid, required this.name});

  final String fromUid;
  final String name;
}

/// Receives invitation links — `shadchan-invite://join?from=<uid>&name=<name>`
/// opened from the page at `shadchan-gilad.web.app/join`, or the same pair
/// carried through a Play Store install as the install referrer.
///
/// **The matchmaker who sent the link gets access by default.** Once the card
/// exists, the personal area grants that one matchmaker access on its own
/// (`CardAccessSections`) — the friend filled in the card *because* this
/// matchmaker asked, so asking them to approve it a second time is a formality.
/// Every other matchmaker still asks and waits. Several matchmakers may invite
/// the same person; the latest invitation is the one honoured, and there is
/// still one account and one card.
abstract final class InviteLinkService {
  static const MethodChannel _channel = MethodChannel('shadchan/invite_links');
  static const String _fromKey = 'invite.from';
  static const String _nameKey = 'invite.name';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<String, Object?> _pending = <String, Object?>{};

  static Box<dynamic>? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box<dynamic>('settings') : null;

  static Object? _read(String key) =>
      _pending.containsKey(key) ? _pending[key] : _box?.get(key);

  /// The invitation waiting for a card to exist, if any.
  static PendingInvite? get pending {
    final Object? from = _read(_fromKey);
    if (from is! String || from.isEmpty) {
      return null;
    }
    final Object? name = _read(_nameKey);
    return PendingInvite(fromUid: from, name: name is String ? name : '');
  }

  /// Reads `from` and `name` out of either an invitation URL or a bare
  /// referrer query string. Null when there is no inviter in it.
  static PendingInvite? parse(String raw) {
    String query = raw.trim();
    final int mark = query.indexOf('?');
    if (mark >= 0) {
      query = query.substring(mark + 1);
    }
    Map<String, String> params;
    try {
      params = Uri.splitQueryString(Uri.decodeComponent(query));
    } catch (_) {
      try {
        params = Uri.splitQueryString(query);
      } catch (_) {
        return null;
      }
    }
    final String from = (params['from'] ?? '').trim();
    if (from.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(from)) {
      return null;
    }
    return PendingInvite(fromUid: from, name: (params['name'] ?? '').trim());
  }

  static void _store(PendingInvite invite) {
    _pending[_fromKey] = invite.fromUid;
    _pending[_nameKey] = invite.name;
    persistHomeSetting(_fromKey, invite.fromUid);
    persistHomeSetting(_nameKey, invite.name);
    revision.value++;
  }

  /// Takes any invitation the platform is holding. Called at launch and on
  /// every resume. A brand-new user who arrived through an invitation is put
  /// on the card owner's route — that is what the link was for.
  ///
  /// Says what arrived, so the caller can move a fresh install from "ברוך
  /// הבא!" to signing in — and send somebody already signed in straight to
  /// their personal area, which is where an invitation or an access request
  /// is answered.
  static Future<InviteArrival> check() async {
    String? raw;
    try {
      raw = await _channel.invokeMethod<String>('takePendingInvite');
      raw ??= await _channel.invokeMethod<String>('takeInstallReferrer');
    } on MissingPluginException {
      return InviteArrival.none;
    } on PlatformException catch (error) {
      debugPrint('InviteLinkService: $error');
      return InviteArrival.none;
    }
    if (raw == null) {
      return InviteArrival.none;
    }
    final PendingInvite? invite = parse(raw);
    if (invite == null) {
      return InviteArrival.none;
    }
    _store(invite);
    if (!SignInPromptStore.hasAccount && WorkspaceStore.entryRoute == null) {
      WorkspaceStore.chooseEntry(EntryRoute.cardOwner);
      return InviteArrival.freshInstall;
    }
    return SignInPromptStore.hasAccount
        ? InviteArrival.signedIn
        : InviteArrival.none;
  }

  /// The invitation was acted on or put aside.
  static void clear() {
    _pending[_fromKey] = '';
    _pending[_nameKey] = '';
    persistHomeSetting(_fromKey, '');
    persistHomeSetting(_nameKey, '');
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _pending.clear();
    revision.value++;
  }
}
