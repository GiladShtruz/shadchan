import 'package:flutter/material.dart';
import 'package:shadchan/widgets/reminders_list.dart';

/// Central list of every proposal that has a reminder set. Reminders themselves
/// are created and edited inside a proposal's detail screen.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('תזכורות'), centerTitle: true),
      body: const RemindersList(),
    );
  }
}
