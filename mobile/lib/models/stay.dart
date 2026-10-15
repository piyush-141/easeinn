import 'guest.dart';
import 'room.dart';

enum StayStatus { active, checkedOut, reserved }

class Stay {
  final String id;
  final String propertyId;
  final String guestId;
  final String roomId;
  final DateTime checkInAt;
  DateTime? checkOutAt;
  final DateTime expectedCheckOut;
  final int numGuests;
  final int numAdults;
  final int numKids;
  final double nightlyRate;
  StayStatus status;
  Guest? guest;
  final List<Guest> coGuests;
  Room? room;

  Stay({
    required this.id,
    required this.propertyId,
    required this.guestId,
    required this.roomId,
    required this.checkInAt,
    this.checkOutAt,
    required this.expectedCheckOut,
    required this.numGuests,
    this.numAdults = 1,
    this.numKids = 0,
    required this.nightlyRate,
    this.status = StayStatus.active,
    this.guest,
    this.coGuests = const [],
    this.room,
  });

  String get guestSummary {
    final parts = <String>[];
    if (numAdults > 0) parts.add('$numAdults Adult${numAdults > 1 ? "s" : ""}');
    if (numKids > 0) parts.add('$numKids Kid${numKids > 1 ? "s" : ""}');
    final breakdown = parts.join(', ');
    final total = numGuests > 0 ? numGuests : (numAdults + numKids);
    return breakdown.isNotEmpty ? '$total Guests ($breakdown)' : '$total Guest${total > 1 ? "s" : ""}';
  }

  int get estimatedNights {
    final diff = expectedCheckOut.difference(checkInAt).inDays;
    return diff <= 0 ? 1 : diff;
  }

  int get actualNights {
    final end = checkOutAt ?? DateTime.now();
    final diff = end.difference(checkInAt).inDays;
    return diff <= 0 ? 1 : diff;
  }
}
