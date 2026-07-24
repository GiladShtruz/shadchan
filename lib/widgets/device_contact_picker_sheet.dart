import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shadchan/services/contacts_import_service.dart';
import 'package:shadchan/utils/phone_utils.dart';

/// A single contact chosen out of the device address book.
class DeviceContactChoice {
  const DeviceContactChoice({required this.name, required this.phone});

  final String name;
  final String phone;
}

/// Bottom sheet for picking one phone number out of the device contacts.
///
/// Unlike the bulk import flows, this picker does not filter or de-duplicate
/// anything — it is used to attach an inquiry contact ("איש קשר לבירורים"),
/// which is often a parent or a friend who is not in the database at all.
class DeviceContactPickerSheet extends StatefulWidget {
  const DeviceContactPickerSheet({super.key});

  static Future<DeviceContactChoice?> show(BuildContext context) {
    return showModalBottomSheet<DeviceContactChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => const DeviceContactPickerSheet(),
    );
  }

  @override
  State<DeviceContactPickerSheet> createState() =>
      _DeviceContactPickerSheetState();
}

class _DeviceContactPickerSheetState extends State<DeviceContactPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  List<DeviceContactChoice> _contacts = <DeviceContactChoice>[];
  bool _isLoading = true;
  String _error = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () => setState(() => _query = _searchController.text.trim()),
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ContactsPermissionState permission =
        await ContactsImportService.requestPermission();
    if (!mounted) {
      return;
    }

    if (permission != ContactsPermissionState.granted) {
      setState(() {
        _isLoading = false;
        _error = permission == ContactsPermissionState.permanentlyDenied
            ? 'הגישה לאנשי הקשר חסומה. אפשר לאשר אותה בהגדרות המכשיר.'
            : 'כדי לבחור איש קשר צריך לאשר גישה לאנשי הקשר.';
      });
      return;
    }

    try {
      final List<Contact> contacts = await FlutterContacts.getAll(
        properties: <ContactProperty>{
          ContactProperty.name,
          ContactProperty.phone,
        },
      );
      if (!mounted) {
        return;
      }

      // Only contacts that actually carry a name and a number are useful here.
      final List<DeviceContactChoice> choices = <DeviceContactChoice>[];
      for (final Contact contact in contacts) {
        final String name = _resolveDisplayName(contact);
        if (name.isEmpty || contact.phones.isEmpty) {
          continue;
        }
        choices.add(
          DeviceContactChoice(
            name: name,
            phone: contact.phones.first.number.trim(),
          ),
        );
      }
      choices.sort(
        (DeviceContactChoice a, DeviceContactChoice b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      setState(() {
        _contacts = choices;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'לא הצלחנו לטעון את אנשי הקשר';
        });
      }
    }
  }

  static String _resolveDisplayName(Contact contact) {
    final String displayName = (contact.displayName ?? '').trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }

    return <String>[
      (contact.name?.first ?? '').trim(),
      (contact.name?.last ?? '').trim(),
    ].where((String part) => part.isNotEmpty).join(' ').trim();
  }

  List<DeviceContactChoice> get _visibleContacts {
    if (_query.isEmpty) {
      return _contacts;
    }
    final String needle = _query.toLowerCase();
    return _contacts.where((DeviceContactChoice contact) {
      return contact.name.toLowerCase().contains(needle) ||
          contact.phone.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'בחירת איש קשר',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'סגירה',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'חיפוש לפי שם או מספר',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(child: _buildList(theme, scrollController)),
          ],
        );
      },
    );
  }

  Widget _buildList(ThemeData theme, ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: Text(
            _error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    final List<DeviceContactChoice> contacts = _visibleContacts;
    if (contacts.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'אין אנשי קשר עם מספר טלפון' : 'לא נמצאו תוצאות',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: contacts.length,
      itemBuilder: (BuildContext context, int index) {
        final DeviceContactChoice contact = contacts[index];
        return ListTile(
          leading: CircleAvatar(child: Text(contact.name[0])),
          title: Text(contact.name),
          subtitle: Text(contact.phone, textDirection: TextDirection.ltr),
          onTap: () => Navigator.of(context).pop(
            DeviceContactChoice(
              name: contact.name,
              // Store the digits only, matching how phones are saved elsewhere.
              phone: PhoneUtils.digitsOnly(contact.phone),
            ),
          ),
        );
      },
    );
  }
}
