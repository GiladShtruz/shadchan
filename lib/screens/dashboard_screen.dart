import 'package:flutter/material.dart';
import 'package:shadchan/widgets/dashboard_summary.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('נתונים'), centerTitle: true),
      body: CustomScrollView(slivers: buildDashboardSummarySlivers(context)),
    );
  }
}
