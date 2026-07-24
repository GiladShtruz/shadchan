import 'package:hive/hive.dart';

part 'match_contact.g.dart';

/// A person tied to a specific proposal (a parent, a friend, a reference) that
/// the matchmaker wants to keep at hand. Picked from the device address book,
/// so it holds just a display name and a phone number.
@HiveType(typeId: 11)
class MatchContact {
  const MatchContact({required this.name, required this.phone});

  @HiveField(0)
  final String name;

  @HiveField(1)
  final String phone;
}
