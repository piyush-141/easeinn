enum RoomStatus { vacant, occupied, needsCleaning, reserved, maintenance }

extension RoomStatusExtension on RoomStatus {
  String get label {
    switch (this) {
      case RoomStatus.vacant:
        return 'Vacant';
      case RoomStatus.occupied:
        return 'Occupied';
      case RoomStatus.needsCleaning:
        return 'Needs Cleaning';
      case RoomStatus.reserved:
        return 'Reserved';
      case RoomStatus.maintenance:
        return 'Maintenance';
    }
  }

  String get dbValue {
    switch (this) {
      case RoomStatus.vacant:
        return 'vacant';
      case RoomStatus.occupied:
        return 'occupied';
      case RoomStatus.needsCleaning:
        return 'needs_cleaning';
      case RoomStatus.reserved:
        return 'reserved';
      case RoomStatus.maintenance:
        return 'maintenance';
    }
  }

  static RoomStatus fromDbValue(String value) {
    switch (value) {
      case 'occupied':
        return RoomStatus.occupied;
      case 'needs_cleaning':
        return RoomStatus.needsCleaning;
      case 'reserved':
        return RoomStatus.reserved;
      case 'maintenance':
        return RoomStatus.maintenance;
      case 'vacant':
      default:
        return RoomStatus.vacant;
    }
  }
}

class Room {
  final String id;
  final String propertyId;
  final String roomNumber;
  final int floor;
  final String categoryName;
  final double baseRate;
  RoomStatus status;
  String? currentGuestName;
  String? currentStayId;
  DateTime? currentCheckInAt;
  DateTime? currentExpectedCheckOut;

  Room({
    required this.id,
    required this.propertyId,
    required this.roomNumber,
    required this.floor,
    required this.categoryName,
    required this.baseRate,
    this.status = RoomStatus.vacant,
    this.currentGuestName,
    this.currentStayId,
    this.currentCheckInAt,
    this.currentExpectedCheckOut,
  });

  Room copyWith({
    String? roomNumber,
    int? floor,
    String? categoryName,
    double? baseRate,
    RoomStatus? status,
    String? currentGuestName,
    String? currentStayId,
    DateTime? currentCheckInAt,
    DateTime? currentExpectedCheckOut,
    bool clearStay = false,
  }) {
    return Room(
      id: id,
      propertyId: propertyId,
      roomNumber: roomNumber ?? this.roomNumber,
      floor: floor ?? this.floor,
      categoryName: categoryName ?? this.categoryName,
      baseRate: baseRate ?? this.baseRate,
      status: status ?? this.status,
      currentGuestName: clearStay ? null : (currentGuestName ?? this.currentGuestName),
      currentStayId: clearStay ? null : (currentStayId ?? this.currentStayId),
      currentCheckInAt: clearStay ? null : (currentCheckInAt ?? this.currentCheckInAt),
      currentExpectedCheckOut: clearStay ? null : (currentExpectedCheckOut ?? this.currentExpectedCheckOut),
    );
  }
}
