import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/card_access_provider.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/providers/inbox_provider.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/whatsapp_utils.dart';
import 'package:shadchan/widgets/app_notice.dart';
import 'package:shadchan/utils/app_navigation.dart';

/// The server's notices about personal cards — a request, an answer, a
/// friend's new card, a wedding, a birthday — on the notifications page.
///
/// A wedding and a birthday carry the one thing worth doing about them: a
/// WhatsApp to the friend, already worded.
class CardInboxList extends StatelessWidget {
  const CardInboxList({super.key, this.onOpen});

  /// Called before navigating away — the bell's panel closes itself with it.
  final VoidCallback? onOpen;

  /// Whether this list draws anything. Watches, like the list itself.
  static bool hasItems(BuildContext context) =>
      _maybe(context)?.items.isNotEmpty ?? false;

  static InboxProvider? _maybe(BuildContext context) {
    try {
      return context.watch<InboxProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _open(
    BuildContext context,
    InboxProvider inbox,
    InboxItem item,
  ) async {
    await inbox.markRead(item);
    if (!context.mounted) {
      return;
    }
    final PersonRepository people = context.read<PersonRepository>();
    final String? owner = item.ownerUid;
    final String? hash = item.ownerPhoneHash;
    final Person? person =
        (owner == null ? null : people.findByCardOwner(owner)) ??
        (hash == null || hash.isEmpty ? null : people.findByPhoneHash(hash));
    if (item.kind == 'cardCreated' && hash != null && hash.isNotEmpty) {
      // The directory said "no card" a minute ago; this notice says otherwise.
      context.read<CardAccessProvider>().forgetLookup(hash);
    }
    onOpen?.call();
    if (person != null) {
      AppNavigation.open(context, '/people/${person.id}');
    } else if (item.route.startsWith('/') && item.route != '/reminders') {
      context.go(item.route);
    }
  }

  Future<void> _whatsApp(BuildContext context, InboxItem item) async {
    final String? owner = item.ownerUid;
    final Person? person = owner == null
        ? null
        : context.read<PersonRepository>().findByCardOwner(owner);
    if (person == null) {
      AppNotice.show(context, 'החבר הזה לא נמצא במאגר שלך');
      return;
    }
    final String name = person.firstName.trim();
    final bool opened = await WhatsAppUtils.openChatWithText(
      person.phone,
      item.kind == 'birthday'
          ? 'מזל טוב ליום ההולדת, $name! 🎂'
          : 'מזל טוב, $name!!! 🎉',
    );
    if (!opened && context.mounted) {
      AppNotice.show(context, 'אין מספר וואטסאפ תקין לחבר הזה');
    }
  }

  @override
  Widget build(BuildContext context) {
    final InboxProvider? inbox = _maybe(context);
    if (inbox == null || inbox.items.isEmpty) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'עדכונים על כרטיסים',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final InboxItem item in inbox.items.take(20))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _open(context, inbox, item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: <Widget>[
                      if (!item.read)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          decoration: const BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.title,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: item.read
                                    ? FontWeight.w500
                                    : FontWeight.w800,
                              ),
                            ),
                            if (item.body.isNotEmpty)
                              Text(item.body, style: theme.textTheme.bodySmall),
                            if (item.offersWhatsApp)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                  onPressed: () => _whatsApp(context, item),
                                  icon: const Icon(
                                    Icons.chat_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    item.kind == 'birthday'
                                        ? 'לשלוח ברכה בוואטסאפ'
                                        : 'לשלוח מזל טוב בוואטסאפ',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'הסרה',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => inbox.remove(item),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
