import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/user_profile_provider.dart';
import 'package:shadchan/services/photo_picker_service.dart';
import 'package:shadchan/utils/app_colors.dart';
import 'package:shadchan/utils/gender_text.dart';
import 'package:shadchan/services/home_board_store.dart';

/// A gentle reminder, on בית, for a matchmaker who skipped the profile photo
/// at sign-up: one line, one button, and a ✕ that puts it away for a month.
///
/// The photo is what other matchmakers recognise — on the profile, in the
/// community, on the leaderboard and when connecting.
class HomePhotoNudge extends StatefulWidget {
  const HomePhotoNudge({super.key});

  /// When the reminder was last put away (ms since epoch), synced with the
  /// account so a second phone does not ask again.
  static const String dismissedKey = 'home.photoNudgeDismissedAt';

  static const Duration rest = Duration(days: 30);

  static bool dismissedRecently({DateTime? now}) {
    if (!Hive.isBoxOpen('settings')) return false;
    final Object? raw = Hive.box<dynamic>('settings').get(dismissedKey);
    final int? at = raw is int ? raw : int.tryParse('$raw');
    if (at == null) return false;
    return (now ?? DateTime.now()).difference(
          DateTime.fromMillisecondsSinceEpoch(at),
        ) <
        rest;
  }

  @override
  State<HomePhotoNudge> createState() => _HomePhotoNudgeState();
}

class _HomePhotoNudgeState extends State<HomePhotoNudge> {
  bool _dismissed = HomePhotoNudge.dismissedRecently();

  void _dismiss() {
    persistHomeSetting(
      HomePhotoNudge.dismissedKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    setState(() => _dismissed = true);
  }

  Future<void> _add(UserProfileProvider profile) async {
    final String? path = await PhotoPickerService.pickSinglePhoto(context);
    if (path == null || !mounted) return;
    await profile.setPhotoPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final UserProfileProvider profile = context.watch<UserProfileProvider>();
    if (_dismissed || profile.photoPath != null) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color blue = dark ? AppColors.primaryDarkDm : AppColors.primary;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: blue.withValues(alpha: dark ? 0.16 : 0.08),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: blue.withValues(alpha: 0.18),
            child: Icon(Icons.add_a_photo_outlined, size: 18, color: blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '{הוסף|הוסיפי} תמונת פרופיל, כדי ששדכנים אחרים יזהו אותך'
                  .forGender(profile.gender),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _add(profile),
            style: TextButton.styleFrom(
              foregroundColor: blue,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('הוספה'),
          ),
          IconButton(
            tooltip: 'לא עכשיו',
            visualDensity: VisualDensity.compact,
            onPressed: _dismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
