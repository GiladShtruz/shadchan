import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/dialogs/contacts_added_celebration.dart';
import 'package:shadchan/providers/add_contacts_session.dart';
import 'package:shadchan/providers/person_repository.dart';
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
  _AddContactsMode _mode = _AddContactsMode.swipe;
  bool _listMounted = false;

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
    final int added = _session?.addedThisSession ?? 0;
    if (added > 1) {
      await ContactsAddedCelebration.show(
        context,
        count: added,
        footnote: 'עדכן את הפרטים שלהם במסך הבית.',
      );
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
                  segments: const <ButtonSegment<_AddContactsMode>>[
                    ButtonSegment<_AddContactsMode>(
                      value: _AddContactsMode.swipe,
                      icon: Icon(Icons.style),
                      label: Text('החלקה'),
                    ),
                    ButtonSegment<_AddContactsMode>(
                      value: _AddContactsMode.list,
                      icon: Icon(Icons.view_list),
                      label: Text('רשימה'),
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
