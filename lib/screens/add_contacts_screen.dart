import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/dialogs/contacts_added_celebration.dart';
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
  int _swipeAddedCount = 0;

  bool get _shouldCelebrate =>
      _mode == _AddContactsMode.swipe && _swipeAddedCount > 1;

  Future<void> _handleLeave() async {
    if (_shouldCelebrate) {
      await ContactsAddedCelebration.show(
        context,
        count: _swipeAddedCount,
        footnote: 'עדכן את הפרטים שלהם במסך הבית.',
      );
      if (!mounted) {
        return;
      }
      _leave();
      return;
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

    return PopScope(
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
          // leading: IconButton(
          //   icon: const Icon(Icons.arrow_back),
          //   tooltip: 'חזרה',
          //   onPressed: _handleLeave,
          // ),
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
                      return BorderSide(color: selectedForeground, width: 1.2);
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
                onAddedCountChanged: (int count) {
                  setState(() => _swipeAddedCount = count);
                },
              ),
              _listMounted
                  ? const ImportContactsScreen(embedded: true)
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
