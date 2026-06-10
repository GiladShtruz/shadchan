import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shadchan/models/person.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/phone_utils.dart';
import 'package:shadchan/widgets/person_avatar.dart';

class PersonListCard extends StatelessWidget {
  const PersonListCard({
    super.key,
    required this.person,
    required this.onTap,
    required this.onOpenMatches,
    required this.onOpenWhatsApp,
    this.onLongPress,
    this.heroEnabled = true,
  });

  final Person person;
  final VoidCallback onTap;
  final VoidCallback onOpenMatches;
  final VoidCallback onOpenWhatsApp;
  final VoidCallback? onLongPress;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasPhone = PhoneUtils.toWhatsAppNumber(person.phone) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsetsDirectional.only(
            start: 16,
            end: 4,
            top: 8,
            bottom: 8,
          ),
          leading: heroEnabled
              ? Hero(
                  tag: 'person-${person.id}',
                  child: PersonAvatar(person: person, radius: 24),
                )
              : PersonAvatar(person: person, radius: 24),
          title: Row(
            children: <Widget>[
              Text(person.profileStatus.emoji),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  person.fullName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          subtitle: _PersonSubtitle(person: person),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (person.isFavorite)
                Icon(Icons.star, color: theme.colorScheme.secondary),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'התאמות',
                icon: Icon(
                  Icons.favorite_outline,
                  color: theme.colorScheme.primary,
                ),
                onPressed: onOpenMatches,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: hasPhone ? 'וואטסאפ' : 'אין מספר טלפון תקין',
                icon: FaIcon(
                  FontAwesomeIcons.whatsapp,
                  size: 20,
                  color: hasPhone
                      ? const Color(0xFF25D366)
                      : theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: hasPhone ? onOpenWhatsApp : null,
              ),
            ],
          ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}

class _PersonSubtitle extends StatelessWidget {
  const _PersonSubtitle({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final List<String> missingInfo = <String>[
      if (person.fullName.trim().isEmpty) 'שם',
      if (person.gender == Gender.unknown) 'מגדר',
      if (person.religiousLevel == null) 'סגנון דתי',
      if (person.age == null) 'גיל',
    ];
    final List<String> parts = <String>[
      if (person.age != null) person.age!.toString(),
      if (person.religiousLevel != null) person.religiousLevel!.displayName,
    ];
    final String inquiryContact = _inquiryContactText(person);

    if (missingInfo.isEmpty && inquiryContact.isEmpty) {
      return Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (parts.isNotEmpty) ...<Widget>[
          Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
        ],
        if (inquiryContact.isNotEmpty) ...<Widget>[
          Text(
            'לבירורים: $inquiryContact',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (missingInfo.isNotEmpty) const SizedBox(height: 6),
        ],
        if (missingInfo.isNotEmpty) _MissingInfoNote(missing: missingInfo),
      ],
    );
  }

  String _inquiryContactText(Person person) {
    final String name = (person.inquiryContactName ?? '').trim();
    final String phone = (person.inquiryContactPhone ?? '').trim();
    if (name.isEmpty && phone.isEmpty) {
      return '';
    }
    if (name.isEmpty) {
      return phone;
    }
    if (phone.isEmpty) {
      return name;
    }
    return '$name · $phone';
  }
}

/// A prominent note listing the details that still need to be filled in for a
/// contact (e.g. "חסר לעדכון: שם · מגדר · גיל").
class _MissingInfoNote extends StatelessWidget {
  const _MissingInfoNote({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'חסר לעדכון: ${missing.join(' · ')}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
