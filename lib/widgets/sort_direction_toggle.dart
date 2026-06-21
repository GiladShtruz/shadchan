import 'package:flutter/material.dart';

/// A small "עולה / יורד" (ascending / descending) selector shown inside the
/// people sort sheets. Reused by the home and people screens so the sort
/// experience stays identical.
class SortDirectionToggle extends StatelessWidget {
  const SortDirectionToggle({
    super.key,
    required this.ascending,
    required this.onChanged,
  });

  final bool ascending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: const <ButtonSegment<bool>>[
          ButtonSegment<bool>(
            value: true,
            label: Text('עולה'),
            icon: Icon(Icons.arrow_upward),
          ),
          ButtonSegment<bool>(
            value: false,
            label: Text('יורד'),
            icon: Icon(Icons.arrow_downward),
          ),
        ],
        selected: <bool>{ascending},
        showSelectedIcon: false,
        onSelectionChanged: (Set<bool> selection) =>
            onChanged(selection.first),
      ),
    );
  }
}
