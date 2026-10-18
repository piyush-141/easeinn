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

  Map<String, dynamic> toJson() => {
    'id': id,
    'property_id': propertyId,
    'guest_id': guestId,
    'room_id': roomId,
    'check_in_at': checkInAt.toIso8601String(),
    'check_out_at': checkOutAt?.toIso8601String(),
    'expected_checkout': expectedCheckOut.toIso8601String(),
    'num_guests': numGuests,
    'num_adults': numAdults,
    'num_kids': numKids,
    'nightly_rate': nightlyRate,
    'status': status == StayStatus.checkedOut
        ? 'checked_out'
        : status == StayStatus.reserved
            ? 'reserved'
            : 'active',
    if (guest != null) 'guest': guest!.toJson(),
    'co_guests': coGuests.map((g) => g.toJson()).toList(),
    if (room != null) 'room': room!.toJson(),
  };

  factory Stay.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status']?.toString();
    StayStatus parsedStatus = StayStatus.active;
    if (statusStr == 'checked_out' || statusStr == 'checkedOut') {
      parsedStatus = StayStatus.checkedOut;
    } else if (statusStr == 'reserved') {
      parsedStatus = StayStatus.reserved;
    }

    final rawCoGuests = json['co_guests'] as List<dynamic>?;
    final List<Guest> coGuestsList = [];
    if (rawCoGuests != null) {
      for (final item in rawCoGuests) {
        if (item is Map<String, dynamic>) {
          coGuestsList.add(Guest.fromJson(item));
        }
      }
    }

    return Stay(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      guestId: json['guest_id']?.toString() ?? '',
      roomId: json['room_id']?.toString() ?? '',
      checkInAt: json['check_in_at'] != null ? DateTime.tryParse(json['check_in_at'].toString()) ?? DateTime.now() : DateTime.now(),
      checkOutAt: json['check_out_at'] != null ? DateTime.tryParse(json['check_out_at'].toString()) : null,
      expectedCheckOut: json['expected_checkout'] != null ? DateTime.tryParse(json['expected_checkout'].toString()) ?? DateTime.now().add(const Duration(days: 1)) : DateTime.now().add(const Duration(days: 1)),
      numGuests: json['num_guests'] is int ? json['num_guests'] : (int.tryParse(json['num_guests']?.toString() ?? '1') ?? 1),
      numAdults: json['num_adults'] is int ? json['num_adults'] : (int.tryParse(json['num_adults']?.toString() ?? '1') ?? 1),
      numKids: json['num_kids'] is int ? json['num_kids'] : (int.tryParse(json['num_kids']?.toString() ?? '0') ?? 0),
      nightlyRate: (json['nightly_rate'] is num) ? (json['nightly_rate'] as num).toDouble() : (double.tryParse(json['nightly_rate']?.toString() ?? '2000') ?? 2000.0),
      status: parsedStatus,
      guest: json['guest'] is Map<String, dynamic> ? Guest.fromJson(json['guest']) : null,
      coGuests: coGuestsList,
      room: json['room'] is Map<String, dynamic> ? Room.fromJson(json['room']) : null,
    );
  }
}
