import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shadchan/providers/person_repository.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int pendingCount = context.watch<PersonRepository>().pendingCount;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            _DrawerHeader(title: 'אנשים', theme: theme),
            ListTile(
              leading: const Icon(Icons.view_list_outlined),
              title: const Text('תצוגת רשימה'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/people');
              },
            ),
            ListTile(
              leading: const Icon(Icons.style_outlined),
              title: const Text('תצוגת החלקה'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/people/import');
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('תצוגת טבלה'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/people?view=table');
              },
            ),
            ListTile(
              leading: Badge.count(
                count: pendingCount,
                isLabelVisible: pendingCount > 0,
                child: const Icon(Icons.inbox_outlined),
              ),
              title: const Text('בהמתנה לעדכון'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/people/pending');
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('מיין לפי'),
              onTap: () async {
                final NavigatorState navigator = Navigator.of(context);
                final String? sort = await _pickSort(context);
                navigator.pop();
                if (sort != null && context.mounted) {
                  context.go('/people?sort=$sort');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('ארכיון (אנשים שהתחתנו)'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/people?archived=true&statuses=mazelTov');
              },
            ),
            const Divider(height: 1),
            _DrawerHeader(title: 'הצעות', theme: theme),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('ארכיון הצעות'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/matches?archived=true');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(
                'הגדרות',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickSort(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: const Text('א-ב'),
                onTap: () => Navigator.of(ctx).pop('alphabetical'),
              ),
              ListTile(
                title: const Text('לפי גיל'),
                onTap: () => Navigator.of(ctx).pop('age'),
              ),
              ListTile(
                title: const Text('חדשים'),
                onTap: () => Navigator.of(ctx).pop('newest'),
              ),
              ListTile(
                title: const Text('עודכנו לאחרונה'),
                onTap: () => Navigator.of(ctx).pop('updated'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
