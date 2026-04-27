import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadchan/screens/import_contacts_screen.dart';
import 'package:shadchan/screens/swipe_import_screen.dart';

enum _AddContactsMode { swipe, list }

class AddContactsScreen extends StatefulWidget {
  const AddContactsScreen({super.key});

  @override
  State<AddContactsScreen> createState() => _AddContactsScreenState();
}

class _AddContactsScreenState extends State<AddContactsScreen> {
  _AddContactsMode _mode = _AddContactsMode.swipe;
  bool _listMounted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('הוספת אנשי קשר'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'הוספת כרטיס שלא מאנשי הקשר',
            onPressed: () => context.push('/people/add'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<_AddContactsMode>(
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
          index: _mode.index,
          children: <Widget>[
            const SwipeImportScreen(embedded: true),
            _listMounted
                ? const ImportContactsScreen(embedded: true)
                : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
