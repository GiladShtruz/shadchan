import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/my_phone_dialog.dart';
import 'package:shadchan/models/card_access.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/providers/personal_card_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/contact_hash_upload.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/services/invite_link_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/phone_identity.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/widgets/settings_widgets.dart';

/// The card owner's side of access, on the personal area: status reports to
/// answer, requests waiting, who can see the card, friends who could, and
/// anybody blocked.
///
/// Nothing here shows the matchmakers' own work — not their ideas, notes,
/// shares or views. The owner sees their card and who may read it; that is
/// all.
class CardAccessSections extends StatefulWidget {
  const CardAccessSections({super.key, required this.hasCard});

  final bool hasCard;

  @override
  State<CardAccessSections> createState() => _CardAccessSectionsState();
}

class _CardAccessSectionsState extends State<CardAccessSections> {
  ContactsPermissionState? _permission;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScan());
  }

  Future<void> _checkAndScan() async {
    ContactsPermissionState state;
    try {
      state = await ContactHashUpload.permission();
    } catch (_) {
      state = ContactsPermissionState.denied;
    }
    if (!mounted) {
      return;
    }
    setState(() => _permission = state);
    if (state == ContactsPermissionState.granted && widget.hasCard) {
      await _scan();
    }
  }

  Future<void> _scan({bool force = false}) async {
    if (_scanning) {
      return;
    }
    setState(() => _scanning = true);
    await ContactHashUpload.run(force: force);
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  /// Contacts are needed only for this: finding friends who match, and
  /// letting the server check that a request comes from a friend.
  Future<void> _askForContacts() async {
    if (_permission == ContactsPermissionState.permanentlyDenied) {
      await ContactsImportService.openSettings();
      return;
    }
    final ContactsPermissionState state =
        await ContactsImportService.requestPermission();
    if (!mounted) {
      return;
    }
    setState(() => _permission = state);
    if (state == ContactsPermissionState.granted) {
      await _scan(force: true);
    }
  }

  void _failed() {
    AppNotice.show(context, 'לא הצלחנו לעדכן כרגע. אפשר לנסות שוב.');
  }

  /// The owner's own number, asked for once if it is missing. Every grant
  /// carries it: it is how the matchmaker's app finds the friend already in
  /// their database — and the number WhatsApp opens — so a grant without it
  /// would add the friend a second time.
  Future<bool> _ensureMyPhone() async {
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    if (profile.myPhone != null) {
      return true;
    }
    final String? phone = await MyPhoneDialog.show(context);
    if (phone == null || !mounted) {
      return false;
    }
    await profile.setMyPhone(phone);
    return true;
  }

  Future<void> _setStatus(
    CardAccessProvider access,
    CardAccess row,
    CardAccessStatus status,
  ) async {
    if (status == CardAccessStatus.approved && !await _ensureMyPhone()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final bool ok = await access.setStatus(
      row,
      status,
      ownerName: profile.fullName,
      ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
      ownerPhone: profile.myPhone,
    );
    if (!ok && mounted) {
      _failed();
    }
  }

  Future<void> _confirmBlock(CardAccessProvider access, CardAccess row) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('לחסום את ${row.matchmakerName}?'),
        content: Text(
          'הגישה לכרטיס תוסר, ולא ניתן יהיה לבקש אותה שוב עד '
                  '{שתבטל|שתבטלי} את החסימה.'
              .forGender(context.userGender),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ביטול'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('חסימה'),
          ),
        ],
      ),
    );
    if (sure == true && mounted) {
      await _setStatus(access, row, CardAccessStatus.blocked);
    }
  }

  Future<void> _grant(CardAccessProvider access, CardHelper helper) async {
    if (!await _ensureMyPhone() || !mounted) {
      return;
    }
    final UserProfileProvider profile = context.read<UserProfileProvider>();
    final bool ok = await access.grant(
      helper,
      ownerName: profile.fullName ?? '',
      ownerPhoneHash: PhoneIdentity.hash(profile.myPhone),
      ownerPhone: profile.myPhone,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      AppNotice.show(context, 'הגישה לכרטיס שלך ניתנה ל${helper.name}');
    } else {
      _failed();
    }
  }

  Future<void> _answer(
    CardAccessProvider access,
    StatusReport report,
    bool confirmed,
  ) async {
    final bool ok = await access.answerReport(
      report,
      confirmed: confirmed,
      cards: context.read<PersonalCardProvider>(),
    );
    if (!ok && mounted) {
      _failed();
    }
  }

  Widget _busyOr(bool busy, Widget child) {
    if (!busy) {
      return child;
    }
    return const SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CardAccessProvider access = context.watch<CardAccessProvider>();
    final Gender? gender = context.userGender;
    final ThemeData theme = Theme.of(context);
    final List<CardAccess> pending = access.pendingRequests;
    final List<CardAccess> approved = access.approved;
    final List<CardAccess> blocked = access.blocked;
    final List<CardHelper> helpers = access.helpers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.hasCard) _InviteSuggestion(access: access, onGrant: _grant),
        if (access.statusReports.isNotEmpty)
          SettingsGroup(
            title: 'עדכוני סטטוס לאישור',
            children: <Widget>[
              for (final StatusReport report in access.statusReports)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${report.matchmakerName} עדכן אצלו שהסטטוס שלך הוא '
                        '‘${_statusLabel(report.status)}’. זה נכון?',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      _busyOr(
                        access.isBusy('report:${report.id}'),
                        Wrap(
                          spacing: 8,
                          children: <Widget>[
                            FilledButton(
                              onPressed: () => _answer(access, report, true),
                              child: const Text('כן, נכון'),
                            ),
                            OutlinedButton(
                              onPressed: () => _answer(access, report, false),
                              child: const Text('לא'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        SettingsGroup(
          title: 'בקשות גישה',
          children: <Widget>[
            if (pending.isEmpty)
              const SettingsRow(
                icon: Icons.mark_email_unread_outlined,
                title: 'אין בקשות חדשות',
              )
            else
              for (final CardAccess row in pending)
                _AccessRow(
                  name: row.matchmakerName,
                  busy: access.isBusy('access:${row.id}'),
                  menu: <String, VoidCallback>{
                    'חסימה': () => _confirmBlock(access, row),
                  },
                  actions: <Widget>[
                    FilledButton(
                      onPressed: () =>
                          _setStatus(access, row, CardAccessStatus.approved),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('לאשר'),
                    ),
                    TextButton(
                      onPressed: () =>
                          _setStatus(access, row, CardAccessStatus.declined),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('לא עכשיו'),
                    ),
                  ],
                ),
          ],
        ),
        SettingsGroup(
          title: 'מי יכול לראות את הכרטיס שלי',
          children: <Widget>[
            if (approved.isEmpty)
              SettingsRow(
                icon: Icons.lock_outline_rounded,
                title: 'רק {אתה|את}'.forGender(gender),
              )
            else
              for (final CardAccess row in approved)
                _AccessRow(
                  name: row.matchmakerName,
                  busy: access.isBusy('access:${row.id}'),
                  menu: <String, VoidCallback>{
                    'הסרת גישה': () =>
                        _setStatus(access, row, CardAccessStatus.revoked),
                    'חסימה': () => _confirmBlock(access, row),
                  },
                ),
          ],
        ),
        if (widget.hasCard)
          SettingsGroup(
            title: 'החברים שלי שכבר בשדכן',
            children: <Widget>[
              if (_permission == null)
                const SizedBox.shrink()
              else if (_permission != ContactsPermissionState.granted)
                SettingsRow(
                  icon: Icons.contacts_outlined,
                  title: 'גישה לאנשי הקשר',
                  subtitle:
                      'כדי למצוא חברים שמשדכים בשדכן, ולוודא שרק חברים שלך '
                      'יכולים לבקש גישה לכרטיס. נשלחים רק מספרים מוצפנים, '
                      'בלי שמות.',
                  trailing: FilledButton(
                    onPressed: _askForContacts,
                    child: Text(
                      _permission == ContactsPermissionState.permanentlyDenied
                          ? 'להגדרות'
                          : 'אישור',
                    ),
                  ),
                )
              else if (_scanning || !access.helpersLoaded)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (helpers.isEmpty)
                const SettingsRow(
                  icon: Icons.diversity_3_outlined,
                  title: 'עוד לא מצאנו חברים שלך בשדכן',
                )
              else
                for (final CardHelper helper in helpers)
                  _HelperRow(
                    name: helper.name,
                    busy: access.isBusy('helper:${helper.uid}'),
                    onGrant: () => _grant(access, helper),
                  ),
            ],
          ),
        if (blocked.isNotEmpty)
          SettingsGroup(
            title: 'חסומים',
            children: <Widget>[
              for (final CardAccess row in blocked)
                SettingsRow(
                  icon: Icons.block_outlined,
                  title: row.matchmakerName,
                  trailing: _busyOr(
                    access.isBusy('access:${row.id}'),
                    TextButton(
                      onPressed: () async {
                        if (!await access.unblock(row) && mounted) {
                          _failed();
                        }
                      },
                      child: const Text('ביטול חסימה'),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static String _statusLabel(String name) {
    for (final ProfileStatus status in ProfileStatus.values) {
      if (status.name == name) {
        return status.displayName;
      }
    }
    return name;
  }
}

/// The matchmaker whose invitation brought this person here, offered first —
/// and only when saved in the owner's contacts, like any other grant. An
/// invitation never grants anything by itself.
class _InviteSuggestion extends StatelessWidget {
  const _InviteSuggestion({required this.access, required this.onGrant});

  final CardAccessProvider access;
  final Future<void> Function(CardAccessProvider, CardHelper) onGrant;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: InviteLinkService.revision,
      builder: (BuildContext context, _, _) {
        final PendingInvite? invite = InviteLinkService.pending;
        if (invite == null) {
          return const SizedBox.shrink();
        }
        final bool alreadyApproved = access.approved.any(
          (CardAccess a) => a.matchmakerUid == invite.fromUid,
        );
        if (alreadyApproved) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => InviteLinkService.clear(),
          );
          return const SizedBox.shrink();
        }
        CardHelper? helper;
        for (final CardHelper h in access.helpers) {
          if (h.uid == invite.fromUid) {
            helper = h;
          }
        }
        if (helper == null) {
          return const SizedBox.shrink();
        }
        final CardHelper found = helper;
        final bool busy = access.isBusy('helper:${found.uid}');
        return SettingsGroup(
          title: 'הזמנה',
          children: <Widget>[
            SettingsRow(
              icon: Icons.mail_outline_rounded,
              title: 'הגעת בהזמנה של ${found.name}',
              subtitle: 'לתת ל${found.name} גישה לכרטיס שלך?',
              trailing: busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextButton(
                          onPressed: InviteLinkService.clear,
                          child: const Text('לא עכשיו'),
                        ),
                        FilledButton(
                          onPressed: () async {
                            await onGrant(access, found);
                            InviteLinkService.clear();
                          },
                          child: const Text('לתת גישה'),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A friend who matchmakes in the app: their full name, and the one thing to
/// do about it. Nothing else — the heading above already says who they are.
class _HelperRow extends StatelessWidget {
  const _HelperRow({
    required this.name,
    required this.busy,
    required this.onGrant,
  });

  final String name;
  final bool busy;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name.trim().isEmpty ? 'ללא שם' : name.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: dark ? AppColors.headingInkDm : AppColors.headingInk,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.tonal(
              onPressed: onGrant,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('לתת גישה'),
            ),
        ],
      ),
    );
  }
}

/// One matchmaker on the owner's lists: an initial, their name, and what can
/// be done about them — the main answers as buttons under the name, anything
/// rarer (blocking) behind the menu. No sentence explaining the row: the
/// heading above it already says what the list is.
class _AccessRow extends StatelessWidget {
  const _AccessRow({
    required this.name,
    required this.busy,
    this.actions = const <Widget>[],
    this.menu = const <String, VoidCallback>{},
  });

  final String name;
  final bool busy;
  final List<Widget> actions;
  final Map<String, VoidCallback> menu;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String shown = name.trim().isEmpty ? 'ללא שם' : name.trim();
    final Color ink = dark ? AppColors.headingInkDm : AppColors.headingInk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 17,
                backgroundColor: ink.withValues(alpha: 0.10),
                child: Text(
                  shown.characters.first,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shown,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (menu.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'פעולות',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (String label) => menu[label]?.call(),
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    for (final String label in menu.keys)
                      PopupMenuItem<String>(value: label, child: Text(label)),
                  ],
                ),
            ],
          ),
          if (actions.isNotEmpty && !busy)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 44, top: 2),
              child: Wrap(spacing: 8, runSpacing: 4, children: actions),
            ),
        ],
      ),
    );
  }
}
