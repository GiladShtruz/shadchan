import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/screens/import_contacts_screen.dart';
import 'package:shadchan/screens/swipe_import_screen.dart';
import 'package:shadchan/utils/app_colors.dart';

enum _AddContactsMode { swipe, list, manual }

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
      await _BravoCelebration.show(context, _swipeAddedCount);
      if (!mounted) {
        return;
      }
      context.go('/home');
      return;
    }

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'חזרה',
          onPressed: _handleLeave,
        ),
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
                ButtonSegment<_AddContactsMode>(
                  value: _AddContactsMode.manual,
                  icon: Icon(Icons.person_add_alt),
                  label: Text('ידני'),
                ),
              ],
              selected: <_AddContactsMode>{_mode},
              onSelectionChanged: (Set<_AddContactsMode> selection) {
                final _AddContactsMode next = selection.first;
                if (next == _AddContactsMode.manual) {
                  context.push('/people/add');
                  return;
                }
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

/// A celebratory animated dialog shown after the user adds several contacts in
/// the swipe view, before returning to the home screen.
class _BravoCelebration extends StatefulWidget {
  const _BravoCelebration({required this.count});

  final int count;

  static Future<void> show(BuildContext context, int count) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'בראבו',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => _BravoCelebration(count: count),
      transitionBuilder: (_, Animation<double> animation, _, Widget child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return Transform.scale(
          scale: curved.value,
          child: Opacity(opacity: animation.value.clamp(0.0, 1.0), child: child),
        );
      },
    );
  }

  @override
  State<_BravoCelebration> createState() => _BravoCelebrationState();
}

class _BravoCelebrationState extends State<_BravoCelebration> {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.elasticOut,
              builder: (BuildContext context, double value, Widget? child) {
                return Transform.scale(
                  scale: value,
                  child: Transform.rotate(
                    angle: (1 - value) * 0.6,
                    child: child,
                  ),
                );
              },
              child: const Text('🎉', style: TextStyle(fontSize: 72)),
            ),
            const SizedBox(height: 16),
            Text(
              'בראבו!',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'הוספת ${widget.count} חברים חדשים למאגר שלך!',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'עדכן את הפרטים שלהם במסך הבית.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('מעולה!'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
