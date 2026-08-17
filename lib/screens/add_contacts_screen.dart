import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/community_dialogs.dart';
import 'package:shadchan/dialogs/contacts_added_celebration.dart';
import 'package:shadchan/providers/add_contacts_session.dart';
import 'package:shadchan/providers/person_repository.dart';
import 'package:shadchan/services/community_profile_store.dart';
import 'package:shadchan/screens/import_contacts_screen.dart';
import 'package:shadchan/screens/swipe_import_screen.dart';
import 'package:shadchan/utils/app_colors.dart';

enum _AddContactsMode { swipe, list }

class AddContactsScreen extends StatefulWidget {
  const AddContactsScreen({super.key});

  @override
  State<AddContactsScreen> createState() => _AddContactsScreenState();
}

class _AddContactsScreenState extends State<AddContactsScreen> {
  /// The list leads. Swiping is the more enjoyable way through a long address
  /// book, but it is also the one that asks a decision per contact with no way
  /// to see what is coming — landing on it is a surprise, and a matchmaker who
  /// opened this screen to add three people they already have in mind wants to
  /// find them, not be dealt them one at a time. Swiping stays a tab away.
  _AddContactsMode _mode = _AddContactsMode.list;
  bool _listMounted = true;

  /// The one store both views read and write. Owned here so the two halves of
  /// the screen are literally looking at the same contacts, the same progress
  /// and the same statuses — switching views never reloads or resets anything.
  AddContactsSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) {
      return;
    }
    final AddContactsSession session = AddContactsSession(
      context.read<PersonRepository>(),
    );
    _session = session;
    session.load();
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _handleLeave() async {
    // A back press with contacts ticked undoes the ticking and nothing else.
    // Leaving on the first press throws away a dozen deliberate taps, which is
    // what stops people trusting multi-select at all; a second press, with
    // nothing selected, leaves as before.
    final AddContactsSession? session = _session;
    if (session != null && session.hasSelection) {
      session.clearSelection();
      return;
    }

    final int added = _session?.addedThisSession ?? 0;
    if (added > 1) {
      // Past the notice threshold this whole session counts as one large
      // import and gets the community note instead of the celebration — never
      // both, which is the entire point of routing it through the same store.
      CommunityProfileStore.noteBulkImport(added);
      if (!await BulkImportNoteDialog.maybeShow(context)) {
        if (!mounted) {
          return;
        }
        await ContactsAddedCelebration.show(
          context,
          count: added,
          footnote: 'אפשר להשלים את הפרטים שלהם ממסך הבית.',
        );
      }
      if (!mounted) {
        return;
      }
    }
    _leave();
  }

  /// The screen is reached both by a push (from the home shortcuts) and by a
  /// direct navigation, so fall back to home when there is nothing to pop.
  void _leave() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AddContactsSession? session = _session;
    if (session == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final Color selectedBackground = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary
        : AppColors.primaryDark;
    final Color selectedForeground = theme.brightness == Brightness.dark
        ? AppColors.onSurface
        : AppColors.onPrimary;
    final Color unselectedBackground = theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : AppColors.onPrimary;
    final Color unselectedForeground = theme.brightness == Brightness.dark
        ? theme.colorScheme.onSurface
        : AppColors.primaryDark;

    return ChangeNotifierProvider<AddContactsSession>.value(
      value: session,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) {
            return;
          }
          _handleLeave();
        },
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const Text('הוספת אנשי קשר'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SegmentedButton<_AddContactsMode>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return selectedBackground;
                      }
                      return unselectedBackground;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return selectedForeground;
                      }
                      return unselectedForeground;
                    }),
                    iconColor: WidgetStateProperty.resolveWith<Color?>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return selectedForeground;
                      }
                      return unselectedForeground;
                    }),
                    side: WidgetStateProperty.resolveWith<BorderSide?>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.selected)) {
                        return BorderSide(
                          color: selectedForeground,
                          width: 1.2,
                        );
                      }
                      return BorderSide(
                        color: unselectedForeground.withValues(alpha: 0.45),
                      );
                    }),
                    textStyle: WidgetStatePropertyAll<TextStyle?>(
                      theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // The default view is named first.
                  segments: const <ButtonSegment<_AddContactsMode>>[
                    ButtonSegment<_AddContactsMode>(
                      value: _AddContactsMode.list,
                      icon: Icon(Icons.view_list),
                      label: Text('רשימה'),
                    ),
                    ButtonSegment<_AddContactsMode>(
                      value: _AddContactsMode.swipe,
                      icon: Icon(Icons.style),
                      label: Text('החלקה'),
                    ),
                  ],
                  selected: <_AddContactsMode>{_mode},
                  onSelectionChanged: (Set<_AddContactsMode> selection) {
                    final _AddContactsMode next = selection.first;
                    setState(() {
                      _mode = next;
                      if (next == _AddContactsMode.list) {
                        _listMounted = true;
                      }
                    });
                  },
                ),
              ),
            ),
          ),
          body: SafeArea(
            child: IndexedStack(
              index: _mode == _AddContactsMode.list ? 1 : 0,
              children: <Widget>[
                SwipeImportScreen(
                  embedded: true,
                  isActive: _mode == _AddContactsMode.swipe,
                ),
                _listMounted
                    ? const ImportContactsScreen(embedded: true)
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
