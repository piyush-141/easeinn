import 'package:flutter/foundation.dart';
import '../models/property.dart';
import '../models/room.dart';
import '../models/guest.dart';
import '../models/stay.dart';
import '../models/bill.dart';

class HotelStore extends ChangeNotifier {
  // Current active property
  Property _currentProperty = Property(
    id: 'prop-001',
    name: 'EaseInn Boutique & Suites',
    address: '88 MG Road, Indiranagar',
    city: 'Bengaluru',
    state: 'Karnataka',
    pincode: '560038',
    phone: '+91 98765 43210',
    email: 'frontdesk@easeinn.com',
    totalRooms: 12,
    upiId: 'piyushpal427@okaxis',
    upiPayeeName: 'Piyush Pal',
  );

  List<Property> _properties = [];

  // Authenticated staff user / General Manager
  String staffName = 'Devika Rao';
  String staffRole = 'General Manager';
  String staffEmail = 'devika.rao@easeinn.com';
  String staffPhone = '+91 98450 11223';
  String staffEmployeeId = 'EAS-MGR-009';
  String staffEmergencyContact = '+91 98450 99887';
  String staffCurrentShift = 'Morning (07:00 AM - 03:30 PM)';
  bool notificationCheckInAlerts = true;
  bool notificationPaymentAlerts = true;
  bool notificationDailySummary = true;
  bool biometricAuthEnabled = false;
  String staffPassword = '••••••••';
  DateTime? lastSyncTime = DateTime.now();
  bool isSyncing = false;
  bool isAuthenticated = false;

  // Update Manager / Profile
  void updateStaffProfile({
    required String name,
    required String role,
    required String email,
    required String phone,
    String? employeeId,
    String? emergencyContact,
    String? currentShift,
  }) {
    staffName = name.trim();
    staffRole = role.trim();
    staffEmail = email.trim();
    staffPhone = phone.trim();
    if (employeeId != null) staffEmployeeId = employeeId.trim();
    if (emergencyContact != null) staffEmergencyContact = emergencyContact.trim();
    if (currentShift != null) staffCurrentShift = currentShift.trim();
    notifyListeners();
  }

  void toggleNotifications({bool? checkIn, bool? payment, bool? summary}) {
    if (checkIn != null) notificationCheckInAlerts = checkIn;
    if (payment != null) notificationPaymentAlerts = payment;
    if (summary != null) notificationDailySummary = summary;
    notifyListeners();
  }

  void toggleBiometrics(bool enabled) {
    biometricAuthEnabled = enabled;
    notifyListeners();
  }

  // Change Password
  bool changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    staffPassword = newPassword;
    notifyListeners();
    return true;
  }

  // Cloud & Local Sync simulation
  Future<void> syncData() async {
    isSyncing = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1400));
    lastSyncTime = DateTime.now();
    isSyncing = false;
    notifyListeners();
  }

  // Update Hotel Business Profile
  void updatePropertyDetails({
    required String propertyId,
    required String name,
    required String address,
    required String city,
    required String state,
    required String pincode,
    required String phone,
    required String email,
    required String upiId,
    required String upiPayeeName,
    String? gstNumber,
    String? defaultCheckInTime,
    String? defaultCheckOutTime,
    String? hotelTier,
  }) {
    final index = _properties.indexWhere((p) => p.id == propertyId);
    if (index != -1) {
      final updated = _properties[index].copyWith(
        name: name.trim(),
        address: address.trim(),
        city: city.trim(),
        state: state.trim(),
        pincode: pincode.trim(),
        phone: phone.trim(),
        email: email.trim(),
        upiId: upiId.trim(),
        upiPayeeName: upiPayeeName.trim(),
        gstNumber: gstNumber?.trim(),
        defaultCheckInTime: defaultCheckInTime?.trim(),
        defaultCheckOutTime: defaultCheckOutTime?.trim(),
        hotelTier: hotelTier?.trim(),
      );
      _properties[index] = updated;
      if (_currentProperty.id == propertyId) {
        _currentProperty = updated;
      }
      notifyListeners();
    }
  }

  // Real room inventory
  final List<Room> _rooms = [];
  final List<Guest> _guests = [];
  final List<Stay> _stays = [];
  final List<Bill> _bills = [];
  final List<Payment> _payments = [];

  HotelStore() {
    _properties = [_currentProperty];
    _initializeRooms();
    _seedInitialData();
  }

  void _initializeRooms() {
    _initializeRoomsForProperty(_currentProperty);
  }

  void _initializeRoomsForProperty(Property prop) {
    _rooms.removeWhere((r) => r.propertyId == prop.id);
    final count = prop.totalRooms > 0 ? prop.totalRooms : 12;
    final half = (count / 2).ceil();
    final List<Room> propRooms = [];

    // Floor 1
    for (int i = 1; i <= half && propRooms.length < count; i++) {
      final numStr = '1${i.toString().padLeft(2, '0')}';
      String cat = 'Standard Room';
      double rate = 2200.0;
      if (i > 2 && i <= 4) {
        cat = 'Deluxe Room';
        rate = 3500.0;
      } else if (i > 4) {
        cat = 'Executive Suite';
        rate = 5500.0;
      }
      propRooms.add(Room(
        id: 'r-${prop.id}-$numStr',
        propertyId: prop.id,
        roomNumber: numStr,
        floor: 1,
        categoryName: cat,
        baseRate: rate,
        status: RoomStatus.vacant,
      ));
    }

    // Floor 2
    for (int i = 1; propRooms.length < count; i++) {
      final numStr = '2${i.toString().padLeft(2, '0')}';
      String cat = 'Standard Room';
      double rate = 2200.0;
      if (i > 2 && i <= 4) {
        cat = 'Deluxe Room';
        rate = 3500.0;
      } else if (i > 4) {
        cat = 'Executive Suite';
        rate = 5500.0;
      }
      propRooms.add(Room(
        id: 'r-${prop.id}-$numStr',
        propertyId: prop.id,
        roomNumber: numStr,
        floor: 2,
        categoryName: cat,
        baseRate: rate,
        status: RoomStatus.vacant,
      ));
    }

    _rooms.addAll(propRooms);
  }

  // Default Check-Out & Check-In Times (editable via Settings)
  String defaultCheckOutTime = '11:00 AM';
  String defaultCheckInTime = '12:00 PM';
  final Set<int> _customFloors = {};

  List<int> get floors {
    final set = <int>{..._rooms.map((r) => r.floor), ..._customFloors}.toList();
    set.sort();
    return set.isEmpty ? [1] : set;
  }

  void updateDefaultTimes({String? checkInTime, String? checkOutTime}) {
    if (checkInTime != null) defaultCheckInTime = checkInTime;
    if (checkOutTime != null) defaultCheckOutTime = checkOutTime;
    notifyListeners();
  }

  double get defaultCheckOutHourFraction {
    try {
      final parts = defaultCheckOutTime.split(' ');
      final timeParts = parts[0].split(':');
      var hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      if (isPm && hour < 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return (hour + minute / 60.0) / 24.0;
    } catch (_) {
      return 11.0 / 24.0;
    }
  }

  DateTime applyDefaultCheckOutTime(DateTime date) {
    try {
      final parts = defaultCheckOutTime.split(' ');
      final timeParts = parts[0].split(':');
      var hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      if (isPm && hour < 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return DateTime(date.year, date.month, date.day, 11, 0);
    }
  }

  DateTime applyDefaultCheckInTime(DateTime date) {
    try {
      final parts = defaultCheckInTime.split(' ');
      final timeParts = parts[0].split(':');
      var hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      if (isPm && hour < 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return DateTime(date.year, date.month, date.day, 12, 0);
    }
  }

  void addFloor(int floorNumber) {
    _customFloors.add(floorNumber);
    notifyListeners();
  }

  bool deleteFloor(int floorNumber) {
    final hasActiveStay = _stays.any((s) => s.status == StayStatus.active && s.room?.floor == floorNumber);
    if (hasActiveStay) return false;
    _rooms.removeWhere((r) => r.floor == floorNumber);
    _customFloors.remove(floorNumber);
    notifyListeners();
    return true;
  }

  void addRoom({
    required String roomNumber,
    required int floor,
    required String categoryName,
    required double baseRate,
  }) {
    final newRoom = Room(
      id: 'r-${DateTime.now().millisecondsSinceEpoch}',
      propertyId: _currentProperty.id,
      roomNumber: roomNumber.trim(),
      floor: floor,
      categoryName: categoryName,
      baseRate: baseRate,
      status: RoomStatus.vacant,
    );
    _rooms.add(newRoom);
    _rooms.sort((a, b) {
      if (a.floor != b.floor) return a.floor.compareTo(b.floor);
      return a.roomNumber.compareTo(b.roomNumber);
    });
    notifyListeners();
  }

  bool deleteRoom(String roomId) {
    final hasActiveStay = _stays.any((s) => s.roomId == roomId && s.status == StayStatus.active);
    if (hasActiveStay) return false;
    _rooms.removeWhere((r) => r.id == roomId);
    notifyListeners();
    return true;
  }

  void _seedInitialData() {
    // Demo seed data is strictly isolated to the built-in demo hotel ('prop-001').
    // Any newly created manager/hotel accounts will NEVER be polluted with demo guests/stays.
    if (_currentProperty.id != 'prop-001') return;
    if (_stays.any((s) => s.propertyId == 'prop-001')) return;
    final now = DateTime.now();

    // Guest 1: Ethan Harper (Room 101) - Checked in 2 days ago at 12:00 PM, checking out tomorrow at 11:00 AM
    final g1 = Guest(
      id: 'g-ethan',
      propertyId: 'prop-001',
      fullName: 'Ethan Harper',
      phone: '+91 98451 23456',
      email: 'ethan.h@example.com',
      idType: 'passport',
      idNumberMasked: 'Z****482',
      dateOfBirth: '1992-05-14',
      gender: 'Male',
      fatherName: 'William Harper',
      address: 'Flat 4B, Kensington Court, Richmond Road, Bengaluru',
      pincode: '560025',
      notes: 'Frequent business traveler, prefers upper floor',
      staysCount: 3,
    );
    _guests.add(g1);

    final r101Index = _rooms.indexWhere((r) => r.roomNumber == '101' && r.propertyId == 'prop-001');
    if (r101Index != -1) {
      final checkIn1 = DateTime(now.year, now.month, now.day - 2, 12, 0); // 12:00 PM
      final checkOut1 = DateTime(now.year, now.month, now.day + 1, 11, 0); // 11:00 AM
      final stay1 = Stay(
        id: 'stay-101',
        propertyId: 'prop-001',
        guestId: g1.id,
        roomId: _rooms[r101Index].id,
        checkInAt: checkIn1,
        expectedCheckOut: checkOut1,
        numGuests: 2,
        numAdults: 2,
        numKids: 0,
        nightlyRate: _rooms[r101Index].baseRate,
        guest: g1,
        room: _rooms[r101Index],
      );
      _stays.add(stay1);
      _rooms[r101Index] = _rooms[r101Index].copyWith(
        status: RoomStatus.occupied,
        currentGuestName: g1.fullName,
        currentStayId: stay1.id,
        currentCheckInAt: checkIn1,
        currentExpectedCheckOut: checkOut1,
      );

      final bill1 = Bill(
        id: 'bill-101',
        stayId: stay1.id,
        billNumber: 'INV-2026-101',
        subtotal: 6600.0,
        amountPaid: 2200.0,
        outstanding: 4400.0,
        status: 'pending',
      );
      _bills.add(bill1);
    }

    // Guest 2: Priya Sharma (with co-guest) (Room 104) - Checked in yesterday at 2:30 PM, checkout in 3 days at 11:00 AM
    final g2 = Guest(
      id: 'g-priya',
      propertyId: 'prop-001',
      fullName: 'Priya Sharma',
      phone: '+91 97412 88990',
      email: 'priya.s@example.com',
      idType: 'aadhaar',
      idNumberMasked: 'XXXX-XXXX-9182',
      dateOfBirth: '1995-11-22',
      gender: 'Female',
      fatherName: 'Rameshwar Sharma',
      address: 'House 14, Sector 7, HSR Layout, Bengaluru',
      pincode: '560102',
      notes: 'Anniversary stay',
      staysCount: 2,
    );
    final g2Co = Guest(
      id: 'g-rajesh',
      propertyId: 'prop-001',
      fullName: 'Rajesh Sharma',
      phone: '+91 97412 88991',
      idType: 'aadhaar',
      idNumberMasked: 'XXXX-XXXX-4321',
      dateOfBirth: '1993-08-19',
      gender: 'Male',
      fatherName: 'Rameshwar Sharma',
      address: 'House 14, Sector 7, HSR Layout, Bengaluru',
      pincode: '560102',
      staysCount: 1,
    );
    _guests.addAll([g2, g2Co]);

    final r104Index = _rooms.indexWhere((r) => r.roomNumber == '104' && r.propertyId == 'prop-001');
    if (r104Index != -1) {
      final checkIn2 = DateTime(now.year, now.month, now.day - 1, 14, 30); // 2:30 PM
      final checkOut2 = DateTime(now.year, now.month, now.day + 3, 11, 0); // 11:00 AM
      final stay2 = Stay(
        id: 'stay-104',
        propertyId: 'prop-001',
        guestId: g2.id,
        roomId: _rooms[r104Index].id,
        checkInAt: checkIn2,
        expectedCheckOut: checkOut2,
        numGuests: 3,
        numAdults: 2,
        numKids: 1,
        nightlyRate: _rooms[r104Index].baseRate,
        guest: g2,
        coGuests: [g2Co],
        room: _rooms[r104Index],
      );
      _stays.add(stay2);
      _rooms[r104Index] = _rooms[r104Index].copyWith(
        status: RoomStatus.occupied,
        currentGuestName: g2.fullName,
        currentStayId: stay2.id,
        currentCheckInAt: checkIn2,
        currentExpectedCheckOut: checkOut2,
      );

      final bill2 = Bill(
        id: 'bill-104',
        stayId: stay2.id,
        billNumber: 'INV-2026-104',
        subtotal: 14000.0,
        amountPaid: 7000.0,
        outstanding: 7000.0,
        status: 'pending',
      );
      _bills.add(bill2);
    }

    // Guest 3: Arjun Kapoor (Upcoming Reservation for Room 201) - Check-in tomorrow at 1:00 PM, checkout in 4 days at 11:00 AM
    final g3 = Guest(
      id: 'g-arjun',
      propertyId: 'prop-001',
      fullName: 'Arjun Kapoor',
      phone: '+91 98200 11223',
      email: 'arjun.k@example.com',
      idType: 'driving_license',
      idNumberMasked: 'DL-04****99',
      dateOfBirth: '1990-03-28',
      gender: 'Male',
      fatherName: 'Sanjay Kapoor',
      address: 'Flat 202, Silver Oak Heights, 100 Feet Road, Indiranagar, Bengaluru',
      pincode: '560038',
      notes: 'VIP guest, late evening arrival confirmed',
      staysCount: 1,
    );
    _guests.add(g3);

    final r201Index = _rooms.indexWhere((r) => r.roomNumber == '201' && r.propertyId == 'prop-001');
    if (r201Index != -1) {
      final checkIn3 = DateTime(now.year, now.month, now.day + 1, 13, 0); // Tomorrow 1:00 PM
      final checkOut3 = DateTime(now.year, now.month, now.day + 4, 11, 0); // 11:00 AM
      final stay3 = Stay(
        id: 'stay-201',
        propertyId: 'prop-001',
        guestId: g3.id,
        roomId: _rooms[r201Index].id,
        checkInAt: checkIn3,
        expectedCheckOut: checkOut3,
        numGuests: 1,
        nightlyRate: _rooms[r201Index].baseRate,
        status: StayStatus.reserved,
        guest: g3,
        room: _rooms[r201Index],
      );
      _stays.add(stay3);
    }

    // Guest 4: Ananya Sen (Upcoming Reservation for Room 205) - Check-in in 3 days at 12:00 PM, checkout in 6 days at 11:00 AM
    final g4 = Guest(
      id: 'g-ananya',
      propertyId: 'prop-001',
      fullName: 'Ananya Sen',
      phone: '+91 99100 44556',
      email: 'ananya.s@example.com',
      idType: 'aadhaar',
      idNumberMasked: 'XXXX-XXXX-8821',
      dateOfBirth: '1998-07-09',
      gender: 'Female',
      fatherName: 'Debashish Sen',
      address: 'Plot 88, Lakeview Residency, Whitefield Main Road, Bengaluru',
      pincode: '560066',
      notes: 'Corporate conference attendee',
      staysCount: 1,
    );
    _guests.add(g4);

    final r205Index = _rooms.indexWhere((r) => r.roomNumber == '205' && r.propertyId == 'prop-001');
    if (r205Index != -1) {
      final checkIn4 = DateTime(now.year, now.month, now.day + 3, 12, 0); // In 3 days 12:00 PM
      final checkOut4 = DateTime(now.year, now.month, now.day + 6, 11, 0); // 11:00 AM
      final stay4 = Stay(
        id: 'stay-205',
        propertyId: 'prop-001',
        guestId: g4.id,
        roomId: _rooms[r205Index].id,
        checkInAt: checkIn4,
        expectedCheckOut: checkOut4,
        numGuests: 2,
        nightlyRate: _rooms[r205Index].baseRate,
        status: StayStatus.reserved,
        guest: g4,
        room: _rooms[r205Index],
      );
      _stays.add(stay4);
    }

    // Room 105: Needs Cleaning (Rahul Verma checked out today at 10:30 AM)
    final r105Index = _rooms.indexWhere((r) => r.roomNumber == '105' && r.propertyId == 'prop-001');
    if (r105Index != -1) {
      _rooms[r105Index] = _rooms[r105Index].copyWith(status: RoomStatus.needsCleaning);
      final g5 = Guest(
        id: 'g-rahul',
        propertyId: 'prop-001',
        fullName: 'Rahul Verma',
        phone: '+91 98111 22334',
        email: 'rahul.verma@example.com',
        idType: 'aadhaar',
        idNumberMasked: 'XXXX-XXXX-1122',
        dateOfBirth: '1987-12-04',
        gender: 'Male',
        fatherName: 'Omprakash Verma',
        address: '45 Brigade Meadows, Kanakapura Main Road, Bengaluru',
        pincode: '560082',
        notes: 'Checked out on time, room in good order',
        staysCount: 4,
      );
      _guests.add(g5);
      final stay5 = Stay(
        id: 'stay-105-past',
        propertyId: 'prop-001',
        guestId: g5.id,
        roomId: _rooms[r105Index].id,
        checkInAt: DateTime(now.year, now.month, now.day - 2, 11, 0),
        expectedCheckOut: DateTime(now.year, now.month, now.day, 10, 30),
        checkOutAt: DateTime(now.year, now.month, now.day, 10, 30),
        numGuests: 1,
        nightlyRate: _rooms[r105Index].baseRate,
        status: StayStatus.checkedOut,
        guest: g5,
        room: _rooms[r105Index],
      );
      _stays.add(stay5);
    }
  }

  // Getters (Strictly scoped to currentProperty)
  Property get currentProperty => _currentProperty;
  List<Property> get properties => _properties;
  List<Room> get rooms => _rooms.where((r) => r.propertyId == _currentProperty.id).toList();
  List<Guest> get guests => _guests.where((g) => g.propertyId == _currentProperty.id).toList();
  List<Stay> get stays => _stays.where((s) => s.propertyId == _currentProperty.id).toList();
  List<Bill> get bills => _bills.where((b) => stays.any((s) => s.id == b.stayId)).toList();
  List<Payment> get payments => _payments.where((p) => bills.any((b) => b.payments.any((bp) => bp.id == p.id))).toList();

  // DYNAMIC COMPUTED METRICS (100% REAL - NO FAKE DATA)
  int get totalRooms => rooms.length;
  int get occupiedRooms => rooms.where((r) => r.status == RoomStatus.occupied).length;
  int get vacantRooms => rooms.where((r) => r.status == RoomStatus.vacant).length;
  int get cleaningRooms => rooms.where((r) => r.status == RoomStatus.needsCleaning).length;
  int get reservedRooms => rooms.where((r) => r.status == RoomStatus.reserved).length;

  int get occupancyRate {
    if (totalRooms == 0) return 0;
    return ((occupiedRooms / totalRooms) * 100).round();
  }

  int get activeGuests {
    return stays
        .where((s) => s.status == StayStatus.active)
        .fold<int>(0, (sum, s) => sum + s.numGuests);
  }

  double get revenueToday {
    final now = DateTime.now();
    return payments
        .where((p) =>
            p.recordedAt.year == now.year &&
            p.recordedAt.month == now.month &&
            p.recordedAt.day == now.day)
        .fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  int get arrivalsToday {
    final now = DateTime.now();
    return stays
        .where((s) =>
            s.checkInAt.year == now.year &&
            s.checkInAt.month == now.month &&
            s.checkInAt.day == now.day)
        .length;
  }

  int get departuresToday {
    final now = DateTime.now();
    return stays
        .where((s) =>
            s.status == StayStatus.active &&
            s.expectedCheckOut.year == now.year &&
            s.expectedCheckOut.month == now.month &&
            s.expectedCheckOut.day == now.day)
        .length;
  }

  List<Stay> get activeStays => stays.where((s) => s.status == StayStatus.active).toList();

  // Upcoming Stays (Scheduled over future days, ordered chronologically by arrival)
  List<Stay> get upcomingStays {
    final now = DateTime.now();
    final list = stays.where((s) {
      return s.status == StayStatus.reserved || (s.status == StayStatus.active && s.checkInAt.isAfter(now));
    }).toList();
    list.sort((a, b) => a.checkInAt.compareTo(b.checkInAt));
    return list;
  }

  // Get stays checking in on a specific date
  List<Stay> getArrivalsForDate(DateTime date) {
    return stays.where((s) {
      return s.checkInAt.year == date.year &&
          s.checkInAt.month == date.month &&
          s.checkInAt.day == date.day;
    }).toList();
  }

  // Get stays checking out on a specific date
  List<Stay> getDeparturesForDate(DateTime date) {
    return stays.where((s) {
      return s.expectedCheckOut.year == date.year &&
          s.expectedCheckOut.month == date.month &&
          s.expectedCheckOut.day == date.day;
    }).toList();
  }

  // Date Insights calculation for any selected date
  Map<String, dynamic> getDateInsights(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day, 0, 0);
    final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final arrivals = getArrivalsForDate(date);
    final departures = getDeparturesForDate(date);

    // Stays active during this date
    final occupiedStays = stays.where((s) {
      if (s.status == StayStatus.checkedOut && s.expectedCheckOut.isBefore(dayStart)) {
        return false;
      }
      return !s.checkInAt.isAfter(dayEnd) && !s.expectedCheckOut.isBefore(dayStart);
    }).toList();

    final occupiedCount = occupiedStays.length.clamp(0, totalRooms);
    final vacantCount = (totalRooms - occupiedCount).clamp(0, totalRooms);
    final occupancyPct = totalRooms > 0 ? ((occupiedCount / totalRooms) * 100).round() : 0;

    return {
      'date': date,
      'occupiedCount': occupiedCount,
      'vacantCount': vacantCount,
      'arrivalsCount': arrivals.length,
      'departuresCount': departures.length,
      'occupancyPct': occupancyPct,
      'arrivals': arrivals,
      'departures': departures,
      'occupiedStays': occupiedStays,
    };
  }

  // ACTIONS

  // 1. Check-In Guest with OCR Data
  Map<String, dynamic> checkInGuest({
    required String roomId,
    required DateTime expectedCheckOut,
    required int numGuests,
    int numAdults = 1,
    int numKids = 0,
    required double nightlyRate,
    required String fullName,
    required String phone,
    String? email,
    required String idType,
    required String idNumber,
    String? dateOfBirth,
    String? gender,
    String? address,
    String? pincode,
    String? fatherName,
    required double advanceAmount,
    required String paymentMethod,
    String? paymentRef,
    List<Map<String, dynamic>>? coGuests,
  }) {
    final roomIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex == -1) throw Exception('Room not found');

    final targetRoom = _rooms[roomIndex];
    if (targetRoom.status == RoomStatus.occupied) {
      throw Exception('Room is already occupied');
    }

    final guestId = 'guest-${DateTime.now().millisecondsSinceEpoch}';
    final stayId = 'stay-${DateTime.now().millisecondsSinceEpoch}';
    final billId = 'bill-${DateTime.now().millisecondsSinceEpoch}';
    final billNumber = 'INV-2026-${(_bills.length + 1).toString().padLeft(4, '0')}';

    // Mask ID number
    final maskedId = idNumber.length > 4
        ? 'XXXX-XXXX-${idNumber.substring(idNumber.length - 4)}'
        : idNumber;

    // 1. Create Guest
    final newGuest = Guest(
      id: guestId,
      propertyId: _currentProperty.id,
      fullName: fullName,
      phone: phone,
      email: email,
      idType: idType,
      idNumberMasked: maskedId,
      dateOfBirth: dateOfBirth,
      gender: gender,
      address: address,
      pincode: pincode,
      fatherName: fatherName,
    );
    _guests.insert(0, newGuest);

    // Register any additional co-guests
    final List<Guest> registeredCoGuests = [];
    if (coGuests != null) {
      for (int i = 0; i < coGuests.length; i++) {
        final cg = coGuests[i];
        final cgName = (cg['fullName'] as String?)?.trim() ?? '';
        if (cgName.isEmpty) continue;
        final cgIdNum = (cg['idNumber'] as String?)?.trim() ?? '';
        final cgMasked = cgIdNum.length > 4
            ? 'XXXX-XXXX-${cgIdNum.substring(cgIdNum.length - 4)}'
            : cgIdNum;
        final newCg = Guest(
          id: 'guest-${DateTime.now().millisecondsSinceEpoch}-${i + 1}',
          propertyId: _currentProperty.id,
          fullName: cgName,
          phone: (cg['phone'] as String?)?.trim() ?? '',
          idType: (cg['idType'] as String?) ?? 'aadhaar',
          idNumberMasked: cgMasked,
          dateOfBirth: cg['dateOfBirth'] as String?,
          gender: cg['gender'] as String?,
          address: cg['address'] as String?,
          pincode: cg['pincode'] as String?,
          fatherName: cg['fatherName'] as String?,
        );
        _guests.insert(0, newCg);
        registeredCoGuests.add(newCg);
      }
    }

    // 2. Create Stay
    final checkInTime = DateTime.now();
    final resolvedExpectedCheckOut = (expectedCheckOut.hour == 0 && expectedCheckOut.minute == 0)
        ? applyDefaultCheckOutTime(expectedCheckOut)
        : expectedCheckOut;

    final newStay = Stay(
      id: stayId,
      propertyId: _currentProperty.id,
      guestId: guestId,
      roomId: roomId,
      checkInAt: checkInTime,
      expectedCheckOut: resolvedExpectedCheckOut,
      numGuests: numGuests,
      numAdults: numAdults,
      numKids: numKids,
      nightlyRate: nightlyRate,
      status: StayStatus.active,
      guest: newGuest,
      coGuests: registeredCoGuests,
      room: targetRoom,
    );
    _stays.insert(0, newStay);

    // Calculate total duration (calendar nights)
    final checkInDateOnly = DateTime(checkInTime.year, checkInTime.month, checkInTime.day);
    final checkOutDateOnly = DateTime(resolvedExpectedCheckOut.year, resolvedExpectedCheckOut.month, resolvedExpectedCheckOut.day);
    final diffDays = checkOutDateOnly.difference(checkInDateOnly).inDays;
    final nights = diffDays <= 0 ? 1 : diffDays;
    final totalStayAmount = nights * nightlyRate;
    final outstanding = (totalStayAmount - advanceAmount).clamp(0.0, totalStayAmount);

    // 3. Create Bill & Line Item
    final newBill = Bill(
      id: billId,
      stayId: stayId,
      billNumber: billNumber,
      subtotal: totalStayAmount,
      amountPaid: advanceAmount,
      outstanding: outstanding,
      status: 'draft',
      lineItems: [
        BillLineItem(
          id: 'li-${DateTime.now().millisecondsSinceEpoch}',
          description: 'Room Stay ($nights night${nights > 1 ? 's' : ''})',
          quantity: nights,
          unitPrice: nightlyRate,
          amount: totalStayAmount,
        ),
      ],
    );

    // 4. Record advance payment if paid
    if (advanceAmount > 0) {
      final payment = Payment(
        id: 'pay-${DateTime.now().millisecondsSinceEpoch}',
        amount: advanceAmount,
        method: paymentMethod,
        paymentType: 'advance',
        reference: paymentRef,
      );
      newBill.payments.add(payment);
      _payments.insert(0, payment);
    }
    _bills.insert(0, newBill);

    // 5. Update Room to Occupied
    _rooms[roomIndex] = targetRoom.copyWith(
      status: RoomStatus.occupied,
      currentGuestName: fullName,
      currentStayId: stayId,
      currentCheckInAt: checkInTime,
      currentExpectedCheckOut: resolvedExpectedCheckOut,
    );

    notifyListeners();

    return {
      'stayId': stayId,
      'billNumber': billNumber,
      'guestName': fullName,
      'roomNumber': targetRoom.roomNumber,
      'totalAmount': totalStayAmount,
      'advancePaid': advanceAmount,
      'coGuestsCount': registeredCoGuests.length,
      'checkInAt': checkInTime,
      'expectedCheckOut': resolvedExpectedCheckOut,
    };
  }

  // 1b. Check if Room is Available for a Specific Future Date Range
  bool isRoomAvailableForDates(String roomId, DateTime startDate, DateTime endDate, {String? excludeStayId}) {
    final start = DateTime(startDate.year, startDate.month, startDate.day, 12, 0);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 11, 0);

    for (final stay in _stays) {
      if (stay.roomId != roomId) continue;
      if (excludeStayId != null && stay.id == excludeStayId) continue;
      if (stay.status == StayStatus.checkedOut) continue;

      final stayStart = stay.checkInAt;
      final stayEnd = stay.expectedCheckOut;

      // Overlap condition: start < stayEnd and end > stayStart
      if (start.isBefore(stayEnd) && end.isAfter(stayStart)) {
        return false;
      }
    }
    return true;
  }

  // List of rooms available for a future date range
  List<Room> getAvailableRoomsForRange(DateTime startDate, DateTime endDate) {
    return _rooms.where((room) {
      return isRoomAvailableForDates(room.id, startDate, endDate);
    }).toList();
  }

  // 1c. Reserve Room for Future Dates (Reservation workflow)
  Map<String, dynamic> reserveRoom({
    required String roomId,
    required DateTime checkInDate,
    required DateTime checkOutDate,
    required int numGuests,
    int numAdults = 1,
    int numKids = 0,
    required double nightlyRate,
    required String fullName,
    required String phone,
    String? email,
    required String idType,
    required String idNumber,
    String? dateOfBirth,
    String? gender,
    String? address,
    String? pincode,
    String? fatherName,
    required double advanceAmount,
    required String paymentMethod,
    String? paymentRef,
    List<Map<String, dynamic>>? coGuests,
    String? specialRequests,
  }) {
    final roomIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex == -1) throw Exception('Room not found');

    if (!isRoomAvailableForDates(roomId, checkInDate, checkOutDate)) {
      throw Exception('Room is already reserved or occupied during selected dates');
    }

    final targetRoom = _rooms[roomIndex];
    final guestId = 'guest-${DateTime.now().millisecondsSinceEpoch}';
    final stayId = 'res-${DateTime.now().millisecondsSinceEpoch}';
    final billId = 'bill-${DateTime.now().millisecondsSinceEpoch}';
    final billNumber = 'RES-2026-${(_bills.length + 1).toString().padLeft(4, '0')}';

    final maskedId = idNumber.length > 4
        ? 'XXXX-XXXX-${idNumber.substring(idNumber.length - 4)}'
        : idNumber;

    // 1. Create Guest
    final newGuest = Guest(
      id: guestId,
      propertyId: _currentProperty.id,
      fullName: fullName,
      phone: phone,
      email: email,
      idType: idType,
      idNumberMasked: maskedId,
      dateOfBirth: dateOfBirth,
      gender: gender,
      address: address,
      pincode: pincode,
      fatherName: fatherName,
    );
    _guests.insert(0, newGuest);

    // Co-guests
    final List<Guest> registeredCoGuests = [];
    if (coGuests != null) {
      for (int i = 0; i < coGuests.length; i++) {
        final cg = coGuests[i];
        final cgName = (cg['fullName'] as String?)?.trim() ?? '';
        if (cgName.isEmpty) continue;
        final cgIdNum = (cg['idNumber'] as String?)?.trim() ?? '';
        final cgMasked = cgIdNum.length > 4
            ? 'XXXX-XXXX-${cgIdNum.substring(cgIdNum.length - 4)}'
            : cgIdNum;
        final newCg = Guest(
          id: 'guest-${DateTime.now().millisecondsSinceEpoch}-${i + 1}',
          propertyId: _currentProperty.id,
          fullName: cgName,
          phone: (cg['phone'] as String?)?.trim() ?? '',
          idType: (cg['idType'] as String?) ?? 'aadhaar',
          idNumberMasked: cgMasked,
        );
        _guests.insert(0, newCg);
        registeredCoGuests.add(newCg);
      }
    }

    // 2. Set timing with property defaults
    final resolvedCheckIn = applyDefaultCheckInTime(checkInDate);
    final resolvedCheckOut = applyDefaultCheckOutTime(checkOutDate);

    final newStay = Stay(
      id: stayId,
      propertyId: _currentProperty.id,
      guestId: guestId,
      roomId: roomId,
      checkInAt: resolvedCheckIn,
      expectedCheckOut: resolvedCheckOut,
      numGuests: numGuests,
      numAdults: numAdults,
      numKids: numKids,
      nightlyRate: nightlyRate,
      status: StayStatus.reserved, // Explicit reservation status
      guest: newGuest,
      coGuests: registeredCoGuests,
      room: targetRoom,
    );
    _stays.insert(0, newStay);

    // Bill calculation
    final diffDays = resolvedCheckOut.difference(resolvedCheckIn).inDays;
    final nights = diffDays <= 0 ? 1 : diffDays;
    final totalStayAmount = nights * nightlyRate;
    final outstanding = (totalStayAmount - advanceAmount).clamp(0.0, totalStayAmount);

    final newBill = Bill(
      id: billId,
      stayId: stayId,
      billNumber: billNumber,
      subtotal: totalStayAmount,
      amountPaid: advanceAmount,
      outstanding: outstanding,
      status: 'reserved',
      lineItems: [
        BillLineItem(
          id: 'li-${DateTime.now().millisecondsSinceEpoch}',
          description: 'Advance Booking Reservation ($nights night${nights > 1 ? 's' : ''})',
          quantity: nights,
          unitPrice: nightlyRate,
          amount: totalStayAmount,
        ),
      ],
    );

    if (advanceAmount > 0) {
      final payment = Payment(
        id: 'pay-${DateTime.now().millisecondsSinceEpoch}',
        amount: advanceAmount,
        method: paymentMethod,
        paymentType: 'advance',
        reference: paymentRef,
      );
      newBill.payments.add(payment);
      _payments.insert(0, payment);
    }
    _bills.insert(0, newBill);

    // If reservation starts today, mark room as reserved
    final now = DateTime.now();
    final isToday = resolvedCheckIn.year == now.year &&
        resolvedCheckIn.month == now.month &&
        resolvedCheckIn.day == now.day;
    if (isToday && targetRoom.status == RoomStatus.vacant) {
      _rooms[roomIndex] = targetRoom.copyWith(status: RoomStatus.reserved);
    }

    notifyListeners();

    return {
      'stayId': stayId,
      'billNumber': billNumber,
      'guestName': fullName,
      'roomNumber': targetRoom.roomNumber,
      'totalAmount': totalStayAmount,
      'advancePaid': advanceAmount,
      'coGuestsCount': registeredCoGuests.length,
      'checkInAt': resolvedCheckIn,
      'expectedCheckOut': resolvedCheckOut,
      'isReservation': true,
    };
  }

  // 1d. Convert Future Reservation into Active Check-In when guest arrives
  void checkInReservedStay(String stayId) {
    final stayIndex = _stays.indexWhere((s) => s.id == stayId);
    if (stayIndex == -1) throw Exception('Reservation not found');
    final targetStay = _stays[stayIndex];
    final roomIndex = _rooms.indexWhere((r) => r.id == targetStay.roomId);

    targetStay.status = StayStatus.active;
    if (roomIndex != -1) {
      _rooms[roomIndex] = _rooms[roomIndex].copyWith(
        status: RoomStatus.occupied,
        currentGuestName: targetStay.guest?.fullName,
        currentStayId: stayId,
        currentCheckInAt: DateTime.now(),
        currentExpectedCheckOut: targetStay.expectedCheckOut,
      );
    }
    notifyListeners();
  }

  // 1e. Cancel Reservation
  void cancelReservation(String stayId) {
    final stayIndex = _stays.indexWhere((s) => s.id == stayId);
    if (stayIndex != -1) {
      final stay = _stays[stayIndex];
      stay.status = StayStatus.checkedOut;
      final roomIndex = _rooms.indexWhere((r) => r.id == stay.roomId);
      if (roomIndex != -1 && _rooms[roomIndex].status == RoomStatus.reserved) {
        _rooms[roomIndex] = _rooms[roomIndex].copyWith(
          status: RoomStatus.vacant,
          clearStay: true,
        );
      }
      notifyListeners();
    }
  }

  // 2. Check-Out Guest & Settle Bill
  Bill checkOutGuest({
    required String stayId,
    required double paymentAmount,
    required String paymentMethod,
  }) {
    final stayIndex = _stays.indexWhere((s) => s.id == stayId);
    if (stayIndex == -1) throw Exception('Active stay not found');

    final targetStay = _stays[stayIndex];
    final roomIndex = _rooms.indexWhere((r) => r.id == targetStay.roomId);

    // Finalize stay
    targetStay.status = StayStatus.checkedOut;
    targetStay.checkOutAt = DateTime.now();

    // Settle bill
    final billIndex = _bills.indexWhere((b) => b.stayId == stayId);
    Bill bill;
    if (billIndex != -1) {
      bill = _bills[billIndex];
      if (paymentAmount > 0) {
        final payment = Payment(
          id: 'pay-${DateTime.now().millisecondsSinceEpoch}',
          amount: paymentAmount,
          method: paymentMethod,
          paymentType: 'full',
        );
        bill.payments.add(payment);
        _payments.insert(0, payment);
      }
      bill.amountPaid += paymentAmount;
      bill.outstanding = (bill.subtotal - bill.amountPaid).clamp(0.0, bill.subtotal);
      bill.status = 'finalized';
    } else {
      bill = Bill(
        id: 'bill-${DateTime.now().millisecondsSinceEpoch}',
        stayId: stayId,
        billNumber: 'INV-2026-FINAL',
        subtotal: targetStay.nightlyRate,
        amountPaid: targetStay.nightlyRate,
        outstanding: 0,
        status: 'finalized',
      );
      _bills.insert(0, bill);
    }

    // Mark room as needs cleaning
    if (roomIndex != -1) {
      _rooms[roomIndex] = _rooms[roomIndex].copyWith(
        status: RoomStatus.needsCleaning,
        clearStay: true,
      );
    }

    notifyListeners();
    return bill;
  }

  // 3. Mark Room as Clean (Housekeeping)
  void markRoomClean(String roomId) {
    final index = _rooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(
        status: RoomStatus.vacant,
        clearStay: true,
      );
      notifyListeners();
    }
  }

  // 4. Update room status directly
  void updateRoomStatus(String roomId, RoomStatus status) {
    final index = _rooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(
        status: status,
        clearStay: status == RoomStatus.vacant || status == RoomStatus.needsCleaning,
      );
      notifyListeners();
    }
  }

  // 4b. Update room core details (number, category, floor, rate)
  void updateRoomDetails({
    required String roomId,
    String? roomNumber,
    String? categoryName,
    int? floor,
    double? baseRate,
    RoomStatus? status,
  }) {
    final index = _rooms.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(
        roomNumber: roomNumber,
        categoryName: categoryName,
        floor: floor,
        baseRate: baseRate,
        status: status,
      );
      notifyListeners();
    }
  }

  // 5. Add New Hotel Property
  Property addNewProperty({
    required String name,
    required String city,
    required String state,
    required String address,
    required String phone,
    required String email,
    required int totalRooms,
    String? propertyId,
    String upiId = 'piyushpal427@okaxis',
    String upiPayeeName = 'Piyush Pal',
  }) {
    final propId = propertyId ?? 'prop-${DateTime.now().millisecondsSinceEpoch}';
    final newProp = Property(
      id: propId,
      name: name,
      address: address,
      city: city,
      state: state,
      pincode: '560001',
      phone: phone,
      email: email,
      totalRooms: totalRooms > 0 ? totalRooms : 12,
      upiId: upiId.isEmpty ? 'piyushpal427@okaxis' : upiId,
      upiPayeeName: upiPayeeName.isEmpty ? name : upiPayeeName,
    );
    // If the only property was the demo property (prop-001) and we are creating a real hotel,
    // remove the demo property and purge all demo seed data so this account is 100% clean!
    if (_properties.length == 1 && _properties.first.id == 'prop-001') {
      _properties.clear();
      _guests.removeWhere((g) => g.propertyId == 'prop-001');
      _stays.removeWhere((s) => s.propertyId == 'prop-001');
      _bills.removeWhere((b) => b.id.contains('101') || b.id.contains('104') || b.id.contains('105'));
      _payments.clear();
      _rooms.removeWhere((r) => r.propertyId == 'prop-001');
    }
    _properties.add(newProp);
    _currentProperty = newProp;
    _initializeRoomsForProperty(newProp); // Setup fresh vacant rooms for new property
    notifyListeners();
    return newProp;
  }

  /// Reset store cleanly for a newly created or authenticated hotel account.
  /// Guarantees ZERO demo seed data leaks into the new account.
  void initCleanAccount({
    required Property property,
    required String managerName,
    required String managerEmail,
    required String managerPhone,
    String? managerRole,
  }) {
    _currentProperty = property;
    _properties = [property];

    // Purge ALL demo seed data completely
    _guests.removeWhere((g) => g.propertyId == 'prop-001');
    _stays.removeWhere((s) => s.propertyId == 'prop-001');
    _bills.removeWhere((b) => b.id.contains('101') || b.id.contains('104') || b.id.contains('105'));
    _payments.clear();

    // Setup fresh vacant rooms exclusively for this property
    _rooms.clear();
    _initializeRoomsForProperty(property);

    // Update manager details
    staffName = managerName.trim();
    staffEmail = managerEmail.trim();
    staffPhone = managerPhone.trim();
    staffRole = managerRole?.trim() ?? 'General Manager / Owner';
    staffEmployeeId = 'EAS-MGR-001';

    isAuthenticated = true;
    notifyListeners();
  }

  /// Load demo account data (ONLY for frontdesk@easeinn.com)
  void loadDemoAccount() {
    _currentProperty = Property(
      id: 'prop-001',
      name: 'EaseInn Boutique & Suites',
      address: '88 MG Road, Indiranagar',
      city: 'Bengaluru',
      state: 'Karnataka',
      pincode: '560038',
      phone: '+91 98765 43210',
      email: 'frontdesk@easeinn.com',
      totalRooms: 12,
      upiId: 'piyushpal427@okaxis',
      upiPayeeName: 'Piyush Pal',
    );
    _properties = [_currentProperty];
    staffName = 'Devika Rao';
    staffRole = 'General Manager';
    staffEmail = 'frontdesk@easeinn.com';
    staffPhone = '+91 98450 11223';
    staffEmployeeId = 'EAS-MGR-009';

    _rooms.clear();
    _guests.clear();
    _stays.clear();
    _bills.clear();
    _payments.clear();

    _initializeRoomsForProperty(_currentProperty);
    _seedInitialData();
    isAuthenticated = true;
    notifyListeners();
  }

  // Update Branch Bank/UPI Details
  void updatePropertyUpi({
    required String propertyId,
    required String upiId,
    required String payeeName,
  }) {
    final index = _properties.indexWhere((p) => p.id == propertyId);
    if (index != -1) {
      final updated = _properties[index].copyWith(
        upiId: upiId.trim(),
        upiPayeeName: payeeName.trim(),
      );
      _properties[index] = updated;
      if (_currentProperty.id == propertyId) {
        _currentProperty = updated;
      }
      notifyListeners();
    }
  }

  // 6. Switch Hotel Property
  void switchProperty(String propertyId) {
    final found = _properties.firstWhere((p) => p.id == propertyId, orElse: () => _currentProperty);
    _currentProperty = found;
    if (!_rooms.any((r) => r.propertyId == found.id)) {
      _initializeRoomsForProperty(found);
    }
    notifyListeners();
  }

  void setCurrentProperty(Property property) {
    if (property.id != 'prop-001') {
      _properties.removeWhere((p) => p.id == 'prop-001');
      _guests.removeWhere((g) => g.propertyId == 'prop-001');
      _stays.removeWhere((s) => s.propertyId == 'prop-001');
      _bills.removeWhere((b) => b.id.contains('101') || b.id.contains('104') || b.id.contains('105'));
      _rooms.removeWhere((r) => r.propertyId == 'prop-001');
    }
    _currentProperty = property;
    if (!_properties.any((p) => p.id == property.id)) {
      _properties.insert(0, property);
    }
    if (!_rooms.any((r) => r.propertyId == property.id)) {
      _initializeRoomsForProperty(property);
    }
    notifyListeners();
  }

  // 7. Login / Logout
  void login({required String email, required String password}) {
    isAuthenticated = true;
    notifyListeners();
  }

  void logout() {
    isAuthenticated = false;
    _currentProperty = Property(
      id: 'prop-001',
      name: 'EaseInn Boutique & Suites',
      address: '88 MG Road, Indiranagar',
      city: 'Bengaluru',
      state: 'Karnataka',
      pincode: '560038',
      phone: '+91 98765 43210',
      email: 'frontdesk@easeinn.com',
      totalRooms: 12,
      upiId: 'piyushpal427@okaxis',
      upiPayeeName: 'Piyush Pal',
    );
    _properties = [_currentProperty];
    staffName = 'Devika Rao';
    staffRole = 'General Manager';
    staffEmail = 'frontdesk@easeinn.com';
    staffPhone = '+91 98450 11223';
    staffEmployeeId = 'EAS-MGR-009';
    _rooms.clear();
    _guests.clear();
    _stays.clear();
    _bills.clear();
    _payments.clear();
    _initializeRoomsForProperty(_currentProperty);
    _seedInitialData();
    notifyListeners();
  }
}
