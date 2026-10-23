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
    String? id,
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
      id: id ?? this.id,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'property_id': propertyId,
    'room_number': roomNumber,
    'floor': floor,
    'category_name': categoryName,
    'base_rate': baseRate,
    'status': status.dbValue,
    'current_guest_name': currentGuestName,
    'current_stay_id': currentStayId,
    'current_check_in_at': currentCheckInAt?.toIso8601String(),
    'current_expected_checkout': currentExpectedCheckOut?.toIso8601String(),
  };

  factory Room.fromJson(Map<String, dynamic> json) => Room(
    id: json['id']?.toString() ?? '',
    propertyId: json['property_id']?.toString() ?? '',
    roomNumber: json['room_number']?.toString() ?? '',
    floor: json['floor'] is int ? json['floor'] : (int.tryParse(json['floor']?.toString() ?? '1') ?? 1),
    categoryName: json['category_name']?.toString() ?? 'Standard Room',
    baseRate: (json['base_rate'] is num) ? (json['base_rate'] as num).toDouble() : (double.tryParse(json['base_rate']?.toString() ?? '2000') ?? 2000.0),
    status: RoomStatusExtension.fromDbValue(json['status']?.toString() ?? 'vacant'),
    currentGuestName: json['current_guest_name']?.toString(),
    currentStayId: json['current_stay_id']?.toString(),
    currentCheckInAt: json['current_check_in_at'] != null ? DateTime.tryParse(json['current_check_in_at'].toString()) : null,
    currentExpectedCheckOut: json['current_expected_checkout'] != null ? DateTime.tryParse(json['current_expected_checkout'].toString()) : null,
  );
}
