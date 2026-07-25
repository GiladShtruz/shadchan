import 'package:flutter/material.dart';
import 'package:shadchan/services/contacts_import_service.dart';

/// A compact review list for contacts hidden by the automatic name filter.
class HiddenContactsDialog extends StatefulWidget {
  const HiddenContactsDialog({
    super.key,
    required this.candidates,
    required this.onRestore,
  });

  final List<ContactImportCandidate> candidates;
  final Future<void> Function(ContactImportCandidate candidate) onRestore;

  static Future<void> show(
    BuildContext context, {
    required List<ContactImportCandidate> candidates,
    required Future<void> Function(ContactImportCandidate candidate) onRestore,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          HiddenContactsDialog(candidates: candidates, onRestore: onRestore),
    );
  }

  @override
  State<HiddenContactsDialog> createState() => _HiddenContactsDialogState();
}

class _HiddenContactsDialogState extends State<HiddenContactsDialog> {
  late final List<ContactImportCandidate> _candidates =
      List<ContactImportCandidate>.from(widget.candidates);
  final Set<String> _restoringPhones = <String>{};

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text('אנשי קשר מוסתרים'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: _candidates.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('אין אנשי קשר מוסתרים'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final ContactImportCandidate candidate = _candidates[index];
                    final bool restoring = _restoringPhones.contains(
                      candidate.normalizedPhone,
                    );
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(candidate.displayName),
                      subtitle: Text(
                        candidate.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: TextButton.icon(
                        onPressed: restoring ? null : () => _restore(candidate),
                        icon: restoring
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('הצגה'),
                      ),
                    );
                  },
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('סגירה'),
        ),
      ],
    );
  }

  Future<void> _restore(ContactImportCandidate candidate) async {
    setState(() => _restoringPhones.add(candidate.normalizedPhone));
    try {
      await widget.onRestore(candidate);
      if (!mounted) {
        return;
      }
      setState(() {
        _restoringPhones.remove(candidate.normalizedPhone);
        _candidates.removeWhere(
          (ContactImportCandidate item) =>
              item.normalizedPhone == candidate.normalizedPhone,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _restoringPhones.remove(candidate.normalizedPhone));
      }
    }
  }
}
