import 'package:flutter/material.dart';
import 'package:shadchan/widgets/reminders_list.dart';
import 'package:shadchan/widgets/support_inbox_list.dart';

/// Everything waiting for a look: the reports and answers that arrived, then
/// every proposal whose reminder has come due.
///
/// Reminders themselves are set from a proposal's own actions panel; the
/// conversations come from `/support/report` and are answered here or from the
/// feedback console.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('התראות ותזכורות'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: const <Widget>[
          SupportInboxList(),
          RemindersList(padding: EdgeInsets.zero, shrinkWrap: true),
        ],
      ),
    );
  }
}
