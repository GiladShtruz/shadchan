import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/tips_provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/tips_service.dart';
import 'package:shadchan/utils/enums.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/utils/matchmaker_tips.dart';
import 'package:shadchan/widgets/home_blocks.dart';

/// "טיפים לשדכנים" — the whole rotation, in one list.
///
/// The home block shows one tip at a time and moves on by itself, which is
/// right for a workspace and useless for somebody who read one last week and
/// wants it again. This is that list: the tips that ship with the app first,
/// then every approved community tip, each credited to whoever wrote it.
///
/// It reads what is already in memory — `TipsProvider` holds a local cache and
/// refreshes on app open — so opening this screen costs nothing and works on a
/// plane.
class TipsListScreen extends StatelessWidget {
  const TipsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Gender? gender = context.watch<UserProfileProvider>().gender;
    final List<CommunityTip> community = context.watch<TipsProvider>().approved;

    final List<({String text, String? author})> tips =
        <({String text, String? author})>[
          for (final String template in MatchmakerTips.tips)
            (text: template.forGender(gender), author: null),
          for (final CommunityTip tip in community)
            (
              text: tip.text,
              author: tip.authorName.isEmpty ? null : tip.authorName,
            ),
        ];

    return Scaffold(
      appBar: AppBar(title: const Text('טיפים לשדכנים'), centerTitle: true),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          itemCount: tips.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int index) {
            if (index == tips.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => context.push('/profile/tips'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('שליחת טיפ משלך'),
                  ),
                ),
              );
            }

            final ({String text, String? author}) tip = tips[index];
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // The same mark the home block puts at the end of a tip,
                    // for the same reason: in Hebrew the end of the sentence is
                    // its left-hand side, and appending it lets the bidi
                    // algorithm put it there.
                    Text(
                      '${tip.text} $tipMark',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    if (tip.author != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        tip.author!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
