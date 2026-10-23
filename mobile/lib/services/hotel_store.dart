import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/property.dart';
import '../models/room.dart';
import '../models/guest.dart';
import '../models/stay.dart';
import '../models/bill.dart';
import '../models/expense.dart';
import 'whatsapp_service.dart';
import 'local_store_service.dart';
import 'supabase_sync_service.dart';
import 'supabase_service.dart';

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

  // Cloud & Local Sync
  Future<void> syncData() async {
    isSyncing = true;
    notifyListeners();
    try {
      // 1. Immediately persist full state to local disk
      saveToLocalStorage();

      // 2. Synchronize with Supabase if client is active and UUID is valid
      if (SupabaseConfig.isConfigured && SupabaseSyncService.isValidUuid(_currentProperty.id)) {
        // Push all local data to Supabase first (handles offline edits)
        await SupabaseSyncService.pushAllData(
          property: _currentProperty,
          rooms: _rooms,
          guests: _guests,
          stays: _stays,
          expenses: _expenses,
          bills: _bills,
        );

        // Pull remote changes to merge in any changes from other devices
        final remote = await SupabaseSyncService.pullRemoteData(_currentProperty.id);
        if (remote != null) {
          _applyRemoteData(remote);
          saveToLocalStorage();
        }
      }
      lastSyncTime = DateTime.now();
    } catch (e) {
      debugPrint('[HotelStore] syncData notice: $e');
    } finally {
      isSyncing = false;
      notifyListeners();
    }
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
      saveToLocalStorage();
      SupabaseSyncService.syncProperty(updated);
    }
  }

  // Real room inventory
  final List<Room> _rooms = [];
  final List<Guest> _guests = [];
  final List<Stay> _stays = [];
  final List<Bill> _bills = [];
  final List<Payment> _payments = [];
  final List<Expense> _expenses = [];

  List<Expense> get expenses => List.unmodifiable(
      _expenses.where((e) => e.propertyId == _currentProperty.id).toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt)));

  /// Add a new expense and persist to local cache + Supabase
  Future<void> addExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? reference,
    String? notes,
    DateTime? recordedAt,
  }) async {
    final isUuid = SupabaseSyncService.isValidUuid(_currentProperty.id);
    final id = isUuid
        ? SupabaseSyncService.generateUuid()
        : 'exp-${DateTime.now().millisecondsSinceEpoch}';
    final expense = Expense(
      id: id,
      propertyId: _currentProperty.id,
      amount: amount,
      category: category,
      paymentMethod: paymentMethod,
      reference: reference,
      notes: notes,
      addedBy: staffName,
      recordedAt: recordedAt ?? DateTime.now(),
    );
    _expenses.insert(0, expense);
    notifyListeners();
    saveToLocalStorage();
    await SupabaseSyncService.syncExpense(expense);
  }

  /// Delete an expense by ID
  Future<void> deleteExpense(String expenseId) async {
    _expenses.removeWhere((e) => e.id == expenseId);
    notifyListeners();
    saveToLocalStorage();
    await SupabaseSyncService.deleteExpense(expenseId);
  }

  /// Record a payment towards a bill (advance or partial)
  void recordPartialPayment({
    required String billId,
    required double amount,
    required String method,
    String? reference,
  }) {
    final billIndex = _bills.indexWhere((b) => b.id == billId);
    if (billIndex == -1) return;

    final isUuid = SupabaseSyncService.isValidUuid(_currentProperty.id);
    final bill = _bills[billIndex];
    final payment = Payment(
      id: isUuid ? SupabaseSyncService.generateUuid() : 'pay-${DateTime.now().millisecondsSinceEpoch}',
      propertyId: _currentProperty.id,
      billId: bill.id,
      amount: amount,
      method: method,
      paymentType: bill.amountPaid > 0 ? 'partial' : 'advance',
      reference: reference,
      recordedAt: DateTime.now(),
    );
    bill.payments.add(payment);
    _payments.insert(0, payment);

    bill.amountPaid += amount;
    bill.outstanding = (bill.subtotal - bill.amountPaid).clamp(0.0, bill.subtotal);
    if (bill.outstanding <= 0.01) {
      bill.outstanding = 0.0;
    }

    notifyListeners();
    saveToLocalStorage();
    Future.microtask(() async {
      await SupabaseSyncService.syncBill(bill, _currentProperty.id);
      await SupabaseSyncService.syncPayment(payment);
      final stay = _stays.where((s) => s.id == bill.stayId).firstOrNull;
      if (stay != null) {
        await SupabaseSyncService.syncStay(stay, knownRooms: _rooms);
      }
    });
  }

  /// Merge remote expenses fetched from Supabase
  void mergeRemoteExpenses(List<Map<String, dynamic>> remoteList) {
    bool changed = false;
    for (final raw in remoteList) {
      try {
        final exp = Expense.fromJson(raw);
        final idx = _expenses.indexWhere((e) => e.id == exp.id);
        if (idx == -1) {
          _expenses.add(exp);
          changed = true;
        } else {
          _expenses[idx] = exp;
          changed = true;
        }
      } catch (e) {
        debugPrint('[HotelStore] Expense parse notice: $e');
      }
    }
    _expenses.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    if (changed) {
      notifyListeners();
      saveToLocalStorage();
    }
  }

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
    final isUuid = SupabaseSyncService.isValidUuid(prop.id);

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
        id: isUuid ? SupabaseSyncService.generateUuid() : 'r-${prop.id}-$numStr',
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
        id: isUuid ? SupabaseSyncService.generateUuid() : 'r-${prop.id}-$numStr',
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
    saveToLocalStorage();
  }

  bool deleteFloor(int floorNumber) {
    final hasActiveStay = _stays.any((s) => s.status == StayStatus.active && s.room?.floor == floorNumber);
    if (hasActiveStay) return false;
    _rooms.removeWhere((r) => r.floor == floorNumber);
    _customFloors.remove(floorNumber);
    notifyListeners();
    saveToLocalStorage();
    return true;
  }

  void addRoom({
    required String roomNumber,
    required int floor,
    required String categoryName,
    required double baseRate,
  }) {
    final isUuid = SupabaseSyncService.isValidUuid(_currentProperty.id);
    final newRoom = Room(
      id: isUuid ? SupabaseSyncService.generateUuid() : 'r-${DateTime.now().millisecondsSinceEpoch}',
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
    saveToLocalStorage();
    Future.microtask(() async {
      final mapping = await SupabaseSyncService.syncRooms(_currentProperty.id, _rooms);
      final assignedId = mapping[roomNumber.trim()];
      if (assignedId != null) {
        final idx = _rooms.indexWhere((r) => r.roomNumber == roomNumber.trim());
        if (idx != -1) {
          _rooms[idx] = _rooms[idx].copyWith(id: assignedId);
          saveToLocalStorage();
        }
      }
    });
  }

  bool deleteRoom(String roomId) {
    final hasActiveStay = _stays.any((s) => s.roomId == roomId && s.status == StayStatus.active);
    if (hasActiveStay) return false;
    _rooms.removeWhere((r) => r.id == roomId);
    notifyListeners();
    saveToLocalStorage();
    Future.microtask(() async {
      await SupabaseSyncService.deleteRoom(_currentProperty.id, roomId);
    });
    return true;
  }

  void _seedInitialData() {
    // Demo seed data is strictly isolated to the built-in demo hotel ('prop-001').
    // Any newly created manager/hotel accounts will NEVER be polluted with demo guests/stays.
    if (_currentProperty.id != 'prop-001') return;
    if (_stays.any((s) => s.propertyId == 'prop-001')) return;
    final now = DateTime.now();

    // Guest 1: Rahul Sharma (Room 101) - Checked in 2 days ago at 12:00 PM, checking out tomorrow at 11:00 AM
    final g1 = Guest(
      id: 'g-ethan',
      propertyId: 'prop-001',
      fullName: 'Rahul Sharma',
      phone: '+91 98451 23456',
      email: 'rahul.s@example.com',
      idType: 'passport',
      idNumberMasked: 'Z****482',
      idNumber: 'Z8471482',
      dateOfBirth: '1992-05-14',
      gender: 'Male',
      fatherName: 'William Sharma',
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
        billNumber: 'BK-1042',
        subtotal: 6400.0,
        amountPaid: 2000.0,
        outstanding: 4400.0,
        status: 'pending',
      );
      final pay1 = Payment(
        id: 'pay-101',
        propertyId: 'prop-001',
        billId: bill1.id,
        amount: 2000.0,
        method: 'upi',
        paymentType: 'advance',
        recordedAt: DateTime(now.year, now.month, now.day, 10, 42),
      );
      bill1.payments.add(pay1);
      _payments.add(pay1);
      _bills.add(bill1);
    }

    // Guest 2: Priya Deshmukh (with co-guest) (Room 104) - Checked in yesterday at 2:30 PM, checkout in 3 days at 11:00 AM
    final g2 = Guest(
      id: 'g-priya',
      propertyId: 'prop-001',
      fullName: 'Priya Deshmukh',
      phone: '+91 97412 88990',
      email: 'priya.d@example.com',
      idType: 'aadhaar',
      idNumberMasked: 'XXXX-XXXX-9182',
      idNumber: '9182-5501-9182',
      dateOfBirth: '1995-11-22',
      gender: 'Female',
      fatherName: 'Rameshwar Deshmukh',
      address: 'House 14, Sector 7, HSR Layout, Bengaluru',
      pincode: '560102',
      notes: 'Anniversary stay',
      staysCount: 2,
    );
    final g2Co = Guest(
      id: 'g-rajesh',
      propertyId: 'prop-001',
      fullName: 'Rajesh Deshmukh',
      phone: '+91 97412 88991',
      idType: 'aadhaar',
      idNumberMasked: 'XXXX-XXXX-4321',
      idNumber: '4321-9988-4321',
      dateOfBirth: '1993-08-19',
      gender: 'Male',
      fatherName: 'Rameshwar Deshmukh',
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
        billNumber: 'BK-1045',
        subtotal: 8500.0,
        amountPaid: 1500.0,
        outstanding: 7000.0,
        status: 'pending',
      );
      final pay2 = Payment(
        id: 'pay-104',
        propertyId: 'prop-001',
        billId: bill2.id,
        amount: 1500.0,
        method: 'upi',
        paymentType: 'advance',
        recordedAt: DateTime(now.year, now.month, now.day - 1, 14, 30),
      );
      bill2.payments.add(pay2);
      _payments.add(pay2);
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
      idNumber: 'DL-04-2018-0099881',
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
      idNumber: '8821-3344-8821',
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
        idNumber: '1122-6677-1122',
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

    // Seed demo expenses for prop-001
    if (_expenses.where((e) => e.propertyId == 'prop-001').isEmpty) {
      _expenses.addAll([
        Expense(
          id: 'exp-demo-01',
          propertyId: 'prop-001',
          amount: 650.0,
          category: 'housekeeping',
          paymentMethod: 'cash',
          notes: 'Laundry Services',
          recordedAt: DateTime(now.year, now.month, now.day, 9, 15),
        ),
        Expense(
          id: 'exp-demo-02',
          propertyId: 'prop-001',
          amount: 2300.0,
          category: 'utilities',
          paymentMethod: 'bank_transfer',
          notes: 'Electricity Bill',
          recordedAt: DateTime(now.year, now.month, now.day - 1, 16, 45),
        ),
      ]);
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
    bool sendWhatsApp = true,
  }) {
    final roomIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex == -1) throw Exception('Room not found');

    final targetRoom = _rooms[roomIndex];
    if (targetRoom.status == RoomStatus.occupied) {
      throw Exception('Room is already occupied');
    }

    final isUuid = SupabaseSyncService.isValidUuid(_currentProperty.id);
    final guestId = isUuid ? SupabaseSyncService.generateUuid() : 'guest-${DateTime.now().millisecondsSinceEpoch}';
    final stayId = isUuid ? SupabaseSyncService.generateUuid() : 'stay-${DateTime.now().millisecondsSinceEpoch}';
    final billId = isUuid ? SupabaseSyncService.generateUuid() : 'bill-${DateTime.now().millisecondsSinceEpoch}';
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
      idNumber: idNumber.trim().isNotEmpty ? idNumber.trim() : null,
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
          id: isUuid ? SupabaseSyncService.generateUuid() : 'guest-${DateTime.now().millisecondsSinceEpoch}-${i + 1}',
          propertyId: _currentProperty.id,
          fullName: cgName,
          phone: (cg['phone'] as String?)?.trim() ?? '',
          email: (cg['email'] as String?)?.trim(),
          idType: (cg['idType'] as String?) ?? 'aadhaar',
          idNumberMasked: cgMasked,
          idNumber: cgIdNum.isNotEmpty ? cgIdNum : null,
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
      propertyId: _currentProperty.id,
      stayId: stayId,
      billNumber: billNumber,
      subtotal: totalStayAmount,
      amountPaid: advanceAmount,
      outstanding: outstanding,
      status: 'draft',
      lineItems: [
        BillLineItem(
          id: isUuid ? SupabaseSyncService.generateUuid() : 'li-${DateTime.now().millisecondsSinceEpoch}',
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
        id: isUuid ? SupabaseSyncService.generateUuid() : 'pay-${DateTime.now().millisecondsSinceEpoch}',
        propertyId: _currentProperty.id,
        billId: billId,
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
    saveToLocalStorage();
    Future.microtask(() async {
      await SupabaseSyncService.syncGuest(newGuest);
      for (final cg in registeredCoGuests) {
        await SupabaseSyncService.syncGuest(cg);
      }
      await SupabaseSyncService.syncStay(newStay, knownRooms: _rooms);
      await SupabaseSyncService.syncBill(newBill, _currentProperty.id);
      await SupabaseSyncService.updateRoomStatus(_currentProperty.id, targetRoom.roomNumber, RoomStatus.occupied);
    });

    // Trigger automated WhatsApp check-in notification (non-blocking)
    if (sendWhatsApp && phone.trim().isNotEmpty) {
      final df = DateFormat('dd MMM yyyy');
      WhatsAppService.triggerCheckIn(
        guestName: fullName,
        phone: phone,
        hotelName: _currentProperty.name,
        roomNumber: targetRoom.roomNumber,
        checkInDate: df.format(checkInTime),
        checkOutDate: df.format(resolvedExpectedCheckOut),
        stayId: stayId,
      );
    }

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
    bool sendWhatsApp = true,
  }) {
    final roomIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (roomIndex == -1) throw Exception('Room not found');

    if (!isRoomAvailableForDates(roomId, checkInDate, checkOutDate)) {
      throw Exception('Room is already reserved or occupied during selected dates');
    }

    final targetRoom = _rooms[roomIndex];
    final isUuid = SupabaseSyncService.isValidUuid(_currentProperty.id);
    final guestId = isUuid ? SupabaseSyncService.generateUuid() : 'guest-${DateTime.now().millisecondsSinceEpoch}';
    final stayId = isUuid ? SupabaseSyncService.generateUuid() : 'res-${DateTime.now().millisecondsSinceEpoch}';
    final billId = isUuid ? SupabaseSyncService.generateUuid() : 'bill-${DateTime.now().millisecondsSinceEpoch}';
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
      idNumber: idNumber.trim().isNotEmpty ? idNumber.trim() : null,
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
          email: (cg['email'] as String?)?.trim(),
          idType: (cg['idType'] as String?) ?? 'aadhaar',
          idNumberMasked: cgMasked,
          idNumber: cgIdNum.isNotEmpty ? cgIdNum : null,
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
      propertyId: _currentProperty.id,
      stayId: stayId,
      billNumber: billNumber,
      subtotal: totalStayAmount,
      amountPaid: advanceAmount,
      outstanding: outstanding,
      status: 'reserved',
      lineItems: [
        BillLineItem(
          id: isUuid ? SupabaseSyncService.generateUuid() : 'li-${DateTime.now().millisecondsSinceEpoch}',
          description: 'Advance Booking Reservation ($nights night${nights > 1 ? 's' : ''})',
          quantity: nights,
          unitPrice: nightlyRate,
          amount: totalStayAmount,
        ),
      ],
    );

    if (advanceAmount > 0) {
      final payment = Payment(
        id: isUuid ? SupabaseSyncService.generateUuid() : 'pay-${DateTime.now().millisecondsSinceEpoch}',
        propertyId: _currentProperty.id,
        billId: billId,
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
    saveToLocalStorage();
    Future.microtask(() async {
      await SupabaseSyncService.syncGuest(newGuest);
      for (final cg in registeredCoGuests) {
        await SupabaseSyncService.syncGuest(cg);
      }
      await SupabaseSyncService.syncStay(newStay, knownRooms: _rooms);
      await SupabaseSyncService.syncBill(newBill, _currentProperty.id);
      if (targetRoom.status == RoomStatus.reserved) {
        await SupabaseSyncService.updateRoomStatus(_currentProperty.id, targetRoom.roomNumber, RoomStatus.reserved);
      }
    });

    // Trigger automated WhatsApp booking confirmation notification (non-blocking)
    if (sendWhatsApp && phone.trim().isNotEmpty) {
      final df = DateFormat('dd MMM yyyy');
      WhatsAppService.triggerReservation(
        guestName: fullName,
        phone: phone,
        hotelName: _currentProperty.name,
        roomNumber: targetRoom.roomNumber,
        checkInDate: df.format(resolvedCheckIn),
        checkOutDate: df.format(resolvedCheckOut),
        stayId: stayId,
      );
    }

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
    final roomIndex = _rooms.indexWhere((r) => r.id == targetStay.roomId || r.roomNumber == targetStay.room?.roomNumber);

    targetStay.status = StayStatus.active;
    if (roomIndex != -1) {
      targetStay.roomId = _rooms[roomIndex].id;
      _rooms[roomIndex] = _rooms[roomIndex].copyWith(
        status: RoomStatus.occupied,
        currentGuestName: targetStay.guest?.fullName,
        currentStayId: stayId,
        currentCheckInAt: DateTime.now(),
        currentExpectedCheckOut: targetStay.expectedCheckOut,
      );
    }
    notifyListeners();
    saveToLocalStorage();
    Future.microtask(() async {
      await SupabaseSyncService.syncStay(targetStay, knownRooms: _rooms);
      if (roomIndex != -1) {
        await SupabaseSyncService.updateRoomStatus(_currentProperty.id, _rooms[roomIndex].roomNumber, RoomStatus.occupied);
      }
    });
  }

  // 1e. Cancel Reservation
  void cancelReservation(String stayId) {
    final stayIndex = _stays.indexWhere((s) => s.id == stayId);
    if (stayIndex != -1) {
      final stay = _stays[stayIndex];
      stay.status = StayStatus.checkedOut;
      final roomIndex = _rooms.indexWhere((r) => r.id == stay.roomId || r.roomNumber == stay.room?.roomNumber);
      if (roomIndex != -1 && _rooms[roomIndex].status == RoomStatus.reserved) {
        _rooms[roomIndex] = _rooms[roomIndex].copyWith(
          status: RoomStatus.vacant,
          clearStay: true,
        );
      }
      notifyListeners();
      saveToLocalStorage();
      Future.microtask(() async {
        await SupabaseSyncService.syncStay(stay, knownRooms: _rooms);
        if (roomIndex != -1) {
          await SupabaseSyncService.updateRoomStatus(_currentProperty.id, _rooms[roomIndex].roomNumber, RoomStatus.vacant);
        }
      });
    }
  }

  // 2. Check-Out Guest & Settle Bill
  Bill checkOutGuest({
    required String stayId,
    required double paymentAmount,
    required String paymentMethod,
    bool sendWhatsApp = true,
    String? pdfBase64,
    String? pdfFileName,
  }) {
    final stayIndex = _stays.indexWhere((s) => s.id == stayId);
    if (stayIndex == -1) throw Exception('Active stay not found');

    final targetStay = _stays[stayIndex];
    final roomIndex = _rooms.indexWhere((r) => r.id == targetStay.roomId || r.roomNumber == targetStay.room?.roomNumber);

    // Finalize stay
    targetStay.status = StayStatus.checkedOut;
    targetStay.checkOutAt = DateTime.now();

    // Settle bill
    final billIndex = _bills.indexWhere((b) => b.stayId == stayId);
    Bill bill;
    if (billIndex != -1) {
      bill = _bills[billIndex];
      if (bill.propertyId.isEmpty) {
        bill.propertyId = _currentProperty.id;
      }
      if (!SupabaseSyncService.isValidUuid(bill.id)) {
        final oldBillId = bill.id;
        final newBillId = SupabaseSyncService.generateUuid();
        bill.id = newBillId;
        for (final p in bill.payments) {
          if (p.billId == oldBillId || p.billId == null || p.billId!.isEmpty) {
            p.billId = newBillId;
          }
        }
      }
      if (paymentAmount > 0) {
        final payment = Payment(
          id: SupabaseSyncService.generateUuid(),
          propertyId: _currentProperty.id,
          billId: bill.id,
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
      final billId = SupabaseSyncService.generateUuid();
      bill = Bill(
        id: billId,
        propertyId: _currentProperty.id,
        stayId: stayId,
        billNumber: 'INV-${DateTime.now().millisecondsSinceEpoch}',
        subtotal: targetStay.nightlyRate,
        amountPaid: paymentAmount > 0 ? paymentAmount : targetStay.nightlyRate,
        outstanding: (targetStay.nightlyRate - paymentAmount).clamp(0.0, targetStay.nightlyRate),
        status: 'finalized',
      );
      if (paymentAmount > 0) {
        final payment = Payment(
          id: SupabaseSyncService.generateUuid(),
          propertyId: _currentProperty.id,
          billId: bill.id,
          amount: paymentAmount,
          method: paymentMethod,
          paymentType: 'full',
        );
        bill.payments.add(payment);
        _payments.insert(0, payment);
      }
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
    saveToLocalStorage();
    Future.microtask(() async {
      await SupabaseSyncService.syncStay(targetStay, knownRooms: _rooms);
      await SupabaseSyncService.syncBill(bill);
      for (final p in bill.payments) {
        await SupabaseSyncService.syncPayment(p);
      }
      if (roomIndex != -1) {
        await SupabaseSyncService.updateRoomStatus(_currentProperty.id, _rooms[roomIndex].roomNumber, RoomStatus.needsCleaning);
      }
    });

    // Trigger automated WhatsApp checkout thank-you notification with straight PDF invoice (non-blocking)
    final guestPhone = targetStay.guest?.phone;
    if (sendWhatsApp && guestPhone != null && guestPhone.trim().isNotEmpty) {
      final df = DateFormat('dd MMM yyyy');
      final roomNum = targetStay.room?.roomNumber ?? (roomIndex != -1 ? _rooms[roomIndex].roomNumber : '');
      WhatsAppService.triggerCheckOut(
        guestName: targetStay.guest?.fullName ?? 'Valued Guest',
        phone: guestPhone,
        hotelName: _currentProperty.name,
        roomNumber: roomNum,
        checkInDate: df.format(targetStay.checkInAt),
        checkOutDate: df.format(targetStay.checkOutAt ?? DateTime.now()),
        stayId: stayId,
        pdfBase64: pdfBase64,
        pdfFileName: pdfFileName,
        totalAmount: bill.subtotal,
        amountPaid: bill.amountPaid,
        balanceDue: bill.outstanding,
        paymentMethod: paymentMethod,
      );
    }

    return bill;
  }

  // 3. Mark Room as Clean (Housekeeping)
  void markRoomClean(String roomId) {
    final index = _rooms.indexWhere((r) => r.id == roomId || r.roomNumber == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(
        status: RoomStatus.vacant,
        clearStay: true,
      );
      notifyListeners();
      saveToLocalStorage();
      SupabaseSyncService.updateRoomStatus(_currentProperty.id, _rooms[index].roomNumber, RoomStatus.vacant);
    }
  }

  // 4. Update room status directly
  void updateRoomStatus(String roomId, RoomStatus status) {
    final index = _rooms.indexWhere((r) => r.id == roomId || r.roomNumber == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(
        status: status,
        clearStay: status == RoomStatus.vacant || status == RoomStatus.needsCleaning,
      );
      notifyListeners();
      saveToLocalStorage();
      SupabaseSyncService.updateRoomStatus(_currentProperty.id, _rooms[index].roomNumber, status);
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
    final index = _rooms.indexWhere((r) => r.id == roomId || r.roomNumber == roomId);
    if (index != -1) {
      _rooms[index] = _rooms[index].copyWith(
        roomNumber: roomNumber,
        categoryName: categoryName,
        floor: floor,
        baseRate: baseRate,
        status: status,
      );
      notifyListeners();
      saveToLocalStorage();
      Future.microtask(() async {
        final idMap = await SupabaseSyncService.syncRooms(_currentProperty.id, _rooms);
        for (int i = 0; i < _rooms.length; i++) {
          final mappedId = idMap[_rooms[i].roomNumber];
          if (mappedId != null && _rooms[i].id != mappedId) {
            _rooms[i] = _rooms[i].copyWith(id: mappedId);
          }
        }
        saveToLocalStorage();
      });
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
    WhatsAppService.currentHotelId = property.id;

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
    saveToLocalStorage();
  }

  /// Exports current store state to a JSON-serializable Map
  Map<String, dynamic> exportState() {
    return {
      'property': _currentProperty.toJson(),
      'rooms': _rooms.map((r) => r.toJson()).toList(),
      'guests': _guests.map((g) => g.toJson()).toList(),
      'stays': _stays.map((s) => s.toJson()).toList(),
      'bills': _bills.map((b) => b.toJson()).toList(),
      'payments': _payments.map((p) => p.toJson()).toList(),
      'expenses': _expenses.map((e) => e.toJson()).toList(),
      'staffName': staffName,
      'staffEmail': staffEmail,
      'staffPhone': staffPhone,
      'staffRole': staffRole,
      'staffEmployeeId': staffEmployeeId,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
    };
  }

  /// Restores store state from a JSON Map
  void _applyState(Map<String, dynamic> map) {
    if (map['property'] is Map<String, dynamic>) {
      _currentProperty = Property.fromJson(map['property']);
      if (!_properties.any((p) => p.id == _currentProperty.id)) {
        _properties.add(_currentProperty);
      }
    }

    if (map['rooms'] is List) {
      _rooms.clear();
      for (final r in map['rooms']) {
        if (r is Map<String, dynamic>) _rooms.add(Room.fromJson(r));
      }
    }

    if (map['guests'] is List) {
      _guests.clear();
      for (final g in map['guests']) {
        if (g is Map<String, dynamic>) _guests.add(Guest.fromJson(g));
      }
    }

    if (map['stays'] is List) {
      _stays.clear();
      for (final s in map['stays']) {
        if (s is Map<String, dynamic>) _stays.add(Stay.fromJson(s));
      }
    }

    if (map['bills'] is List) {
      _bills.clear();
      for (final b in map['bills']) {
        if (b is Map<String, dynamic>) _bills.add(Bill.fromJson(b));
      }
    }

    if (map['payments'] is List) {
      _payments.clear();
      for (final p in map['payments']) {
        if (p is Map<String, dynamic>) _payments.add(Payment.fromJson(p));
      }
    }

    if (map['expenses'] is List) {
      _expenses.clear();
      for (final e in map['expenses']) {
        if (e is Map<String, dynamic>) {
          try { _expenses.add(Expense.fromJson(e)); } catch (_) {}
        }
      }
    }

    if (map['staffName'] != null) staffName = map['staffName'].toString();
    if (map['staffEmail'] != null) staffEmail = map['staffEmail'].toString();
    if (map['staffPhone'] != null) staffPhone = map['staffPhone'].toString();
    if (map['staffRole'] != null) staffRole = map['staffRole'].toString();
    if (map['staffEmployeeId'] != null) staffEmployeeId = map['staffEmployeeId'].toString();
    if (map['lastSyncTime'] != null) {
      lastSyncTime = DateTime.tryParse(map['lastSyncTime'].toString());
    }

    _relinkStayRelations();
  }

  void _relinkStayRelations() {
    for (final stay in _stays) {
      if (stay.guest == null) {
        final g = _guests.cast<Guest?>().firstWhere(
          (guest) => guest?.id == stay.guestId,
          orElse: () => null,
        );
        stay.guest = g ?? Guest(
          id: stay.guestId,
          propertyId: stay.propertyId,
          fullName: 'Guest',
          phone: '',
          idType: 'other',
          idNumberMasked: 'XXXX',
        );
      }
      // Heal and link room
      Room? r = _rooms.cast<Room?>().firstWhere(
        (room) => room?.id == stay.roomId,
        orElse: () => null,
      );
      if (r == null && stay.room?.roomNumber != null) {
        r = _rooms.cast<Room?>().firstWhere(
          (room) => room?.roomNumber == stay.room!.roomNumber,
          orElse: () => null,
        );
      }
      if (r == null && stay.roomId.isNotEmpty) {
        r = _rooms.cast<Room?>().firstWhere(
          (room) => room?.roomNumber == stay.roomId,
          orElse: () => null,
        );
      }
      if (r != null) {
        stay.room = r;
        stay.roomId = r.id; // Heal stay.roomId to authoritative room UUID
      } else if (stay.room == null) {
        stay.room = Room(
          id: stay.roomId,
          propertyId: stay.propertyId,
          roomNumber: 'Room',
          floor: 1,
          categoryName: 'Standard',
          baseRate: stay.nightlyRate,
        );
      }
    }
  }

  /// Automatically persists state to disk without blocking the UI
  void saveToLocalStorage() {
    LocalStoreService.saveHotelData(_currentProperty.id, exportState());
  }

  /// Merges remote Supabase records into store
  void applyRemoteData(Map<String, dynamic> remote) {
    _applyRemoteData(remote);
  }

  /// Merges remote Supabase records into store
  /// Remote data uses DB field names: base_rate, category_name, etc.
  void _applyRemoteData(Map<String, dynamic> remote) {
    final remoteRooms = remote['rooms'] as List<dynamic>? ?? [];
    final remoteGuests = remote['guests'] as List<dynamic>? ?? [];
    final remoteStays = remote['stays'] as List<dynamic>? ?? [];

    if (remoteRooms.isNotEmpty) {
      for (final raw in remoteRooms) {
        if (raw is! Map<String, dynamic>) continue;
        final roomNum = raw['room_number']?.toString();
        if (roomNum == null || roomNum.isEmpty) continue;
        final status = RoomStatusExtension.fromDbValue(raw['status']?.toString() ?? 'vacant');
        // DB has base_rate column (after migration 00007) and category_name
        final baseRate = (raw['base_rate'] is num)
            ? (raw['base_rate'] as num).toDouble()
            : (raw['rate_override'] is num ? (raw['rate_override'] as num).toDouble() : 2000.0);
        final categoryName = raw['category_name']?.toString() ?? 'Standard Room';
        final floor = raw['floor'] is int ? raw['floor'] as int : (int.tryParse(raw['floor']?.toString() ?? '1') ?? 1);
        final roomId = raw['id']?.toString() ?? '';

        final index = _rooms.indexWhere((r) => r.roomNumber == roomNum && r.propertyId == _currentProperty.id);
        if (index != -1) {
          // Update status and rate from remote; preserve local room state if occupied
          final existing = _rooms[index];
          _rooms[index] = existing.copyWith(
            id: roomId.isNotEmpty ? roomId : existing.id,
            status: status,
            baseRate: baseRate,
            categoryName: categoryName,
          );
        } else {
          _rooms.add(Room(
            id: roomId.isNotEmpty ? roomId : SupabaseSyncService.generateUuid(),
            propertyId: _currentProperty.id,
            roomNumber: roomNum,
            floor: floor,
            categoryName: categoryName,
            baseRate: baseRate,
            status: status,
          ));
        }
      }
    }

    if (remoteGuests.isNotEmpty) {
      for (final raw in remoteGuests) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          final guest = Guest.fromJson(raw);
          final index = _guests.indexWhere((g) => g.id == guest.id);
          if (index != -1) {
            _guests[index] = guest;
          } else {
            _guests.add(guest);
          }
        } catch (e) {
          debugPrint('[HotelStore] Guest parse notice: $e');
        }
      }
    }

    if (remoteStays.isNotEmpty) {
      for (final raw in remoteStays) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          final stay = Stay.fromJson(raw);
          final index = _stays.indexWhere((s) => s.id == stay.id);
          if (index != -1) {
            _stays[index] = stay;
          } else {
            _stays.add(stay);
          }
        } catch (e) {
          debugPrint('[HotelStore] Stay parse notice: $e');
        }
      }
    }

    // Parse remote bills & payments if available
    final remoteBills = remote['bills'] as List<dynamic>? ?? [];
    if (remoteBills.isNotEmpty) {
      for (final raw in remoteBills) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          final bill = Bill.fromJson(raw);
          final index = _bills.indexWhere((b) => b.id == bill.id);
          if (index != -1) {
            _bills[index] = bill;
          } else {
            _bills.add(bill);
          }
          // Merge bill's nested payments
          for (final p in bill.payments) {
            final pIndex = _payments.indexWhere((pay) => pay.id == p.id);
            if (pIndex != -1) {
              _payments[pIndex] = p;
            } else {
              _payments.add(p);
            }
          }
        } catch (e) {
          debugPrint('[HotelStore] Bill parse notice: $e');
        }
      }
    }

    // Parse remote standalone payments if available
    final remotePayments = remote['payments'] as List<dynamic>? ?? [];
    if (remotePayments.isNotEmpty) {
      for (final raw in remotePayments) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          final payment = Payment.fromJson(raw);
          final pIndex = _payments.indexWhere((pay) => pay.id == payment.id);
          if (pIndex != -1) {
            _payments[pIndex] = payment;
          } else {
            _payments.add(payment);
          }
        } catch (e) {
          debugPrint('[HotelStore] Payment parse notice: $e');
        }
      }
    }

    // Parse remote expenses if available
    final remoteExpenses = remote['expenses'] as List<dynamic>? ?? [];
    if (remoteExpenses.isNotEmpty) {
      mergeRemoteExpenses(remoteExpenses.whereType<Map<String, dynamic>>().toList());
    }

    // Rebuild room occupancy state from active stays
    _reconcileRoomStatusFromStays();
    _relinkStayRelations();
  }

  /// Rebuilds room occupied/reserved status from active stays data
  /// This ensures room status is always consistent with actual stay records
  void _reconcileRoomStatusFromStays() {
    // Reset all rooms to vacant first (only for current property)
    for (int i = 0; i < _rooms.length; i++) {
      if (_rooms[i].propertyId == _currentProperty.id &&
          (_rooms[i].status == RoomStatus.occupied || _rooms[i].status == RoomStatus.reserved)) {
        _rooms[i] = _rooms[i].copyWith(status: RoomStatus.vacant, clearStay: true);
      }
    }

    // Re-apply from stays
    for (final stay in _stays) {
      if (stay.propertyId != _currentProperty.id) continue;
      if (stay.status == StayStatus.checkedOut) continue;

      int roomIndex = _rooms.indexWhere((r) => r.id == stay.roomId);
      if (roomIndex == -1 && stay.room?.roomNumber != null) {
        roomIndex = _rooms.indexWhere((r) => r.roomNumber == stay.room!.roomNumber && r.propertyId == _currentProperty.id);
        if (roomIndex != -1) {
          stay.roomId = _rooms[roomIndex].id;
        }
      }
      if (roomIndex == -1) continue;

      final guestName = stay.guest?.fullName ?? 'Guest';
      if (stay.status == StayStatus.active) {
        _rooms[roomIndex] = _rooms[roomIndex].copyWith(
          status: RoomStatus.occupied,
          currentGuestName: guestName,
          currentStayId: stay.id,
          currentCheckInAt: stay.checkInAt,
          currentExpectedCheckOut: stay.expectedCheckOut,
        );
      } else if (stay.status == StayStatus.reserved) {
        // Only mark reserved if check-in is today or future
        final now = DateTime.now();
        final isCurrentOrFuture = !stay.checkInAt.isBefore(DateTime(now.year, now.month, now.day));
        if (isCurrentOrFuture && _rooms[roomIndex].status == RoomStatus.vacant) {
          _rooms[roomIndex] = _rooms[roomIndex].copyWith(
            status: RoomStatus.reserved,
            currentGuestName: guestName,
            currentStayId: stay.id,
            currentCheckInAt: stay.checkInAt,
            currentExpectedCheckOut: stay.expectedCheckOut,
          );
        }
      }
    }
  }

  // _backgroundSyncWithSupabase and _backgroundPushToSupabase are unified into _backgroundPushAndPull below

  /// Primary account loader: checks local storage first, then Supabase, preventing accidental resets
  /// Flow:
  ///   1. Load from local cache instantly → show UI → push local to Supabase + pull remote
  ///   2. If no local cache → pull from Supabase
  ///   3. If no remote data either → brand new account, initialize clean
  Future<void> loadForProperty({
    required Property property,
    required String managerName,
    required String managerEmail,
    required String managerPhone,
    String? managerRole,
    bool forceRemote = false,
  }) async {
    _currentProperty = property;
    if (!_properties.any((p) => p.id == property.id)) {
      _properties.add(property);
    }
    // CRITICAL: Set hotel ID so WhatsApp sessions are properly isolated per account
    WhatsAppService.currentHotelId = property.id;

    staffName = managerName.trim();
    staffEmail = managerEmail.trim();
    staffPhone = managerPhone.trim();
    if (managerRole != null) staffRole = managerRole.trim();

    // 1. Check local storage (instant cache hit)
    if (!forceRemote) {
      final localData = await LocalStoreService.loadHotelData(property.id);
      if (localData != null) {
        _applyState(localData);
        // _applyState restores the full locally-saved property (with name, UPI, etc.)
        // We only override if the local cache somehow lost the property or has wrong ID
        if (_currentProperty.id != property.id) {
          _currentProperty = property;
        }
        // Always ensure the property list contains this entry
        if (!_properties.any((p) => p.id == property.id)) {
          _properties.add(_currentProperty);
        }
        isAuthenticated = true;
        notifyListeners();
        // Push local offline changes to Supabase AND pull latest remote
        _backgroundPushAndPull();
        return;
      }
    }

    // 2. Demo account check
    if (property.id == 'prop-001') {
      loadDemoAccount();
      saveToLocalStorage();
      return;
    }

    // 3. Check Supabase remote data first
    if (SupabaseConfig.isConfigured && SupabaseSyncService.isValidUuid(property.id)) {
      final remote = await SupabaseSyncService.pullRemoteData(property.id);
      if (remote != null) {
        final hasRooms = (remote['rooms'] as List).isNotEmpty;
        _rooms.clear();
        _guests.clear();
        _stays.clear();
        _bills.clear();
        _payments.clear();
        _expenses.clear();
        _applyRemoteData(remote);
        // If remote had no rooms, initialize default rooms for new property
        if (!hasRooms) {
          _initializeRoomsForProperty(property);
          await SupabaseSyncService.syncRooms(property.id, _rooms);
        }
        await SupabaseSyncService.syncProperty(property);
        isAuthenticated = true;
        saveToLocalStorage();
        notifyListeners();
        return;
      }
    }

    // 4. Truly brand new account: initialize clean rooms and persist
    _rooms.clear();
    _guests.clear();
    _stays.clear();
    _bills.clear();
    _payments.clear();
    _expenses.clear();
    _initializeRoomsForProperty(property);
    isAuthenticated = true;
    notifyListeners();
    saveToLocalStorage();

    // Push initial rooms and property to Supabase
    if (SupabaseConfig.isConfigured && SupabaseSyncService.isValidUuid(property.id)) {
      await SupabaseSyncService.syncProperty(property);
      await SupabaseSyncService.syncRooms(property.id, _rooms);
    }
  }

  /// Push local data to Supabase, then pull latest remote and merge
  /// Called after loading from local cache to sync any offline changes
  void _backgroundPushAndPull() {
    if (!SupabaseConfig.isConfigured || !SupabaseSyncService.isValidUuid(_currentProperty.id)) return;
    Future.microtask(() async {
      try {
        // Push local changes first
        await SupabaseSyncService.pushAllData(
          property: _currentProperty,
          rooms: _rooms,
          guests: _guests,
          stays: _stays,
          expenses: _expenses,
          bills: _bills,
        );
        // Then pull remote to pick up any changes from other devices
        final remote = await SupabaseSyncService.pullRemoteData(_currentProperty.id);
        if (remote != null) {
          _applyRemoteData(remote);
          saveToLocalStorage();
          notifyListeners();
          debugPrint('[HotelStore] Bidirectional sync complete.');
        }
      } catch (e) {
        debugPrint('[HotelStore] Background push+pull notice: $e');
      }
    });
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
    _expenses.clear();

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
    // Reset to empty state — do NOT load demo data or any other user's data
    _currentProperty = Property(
      id: '',
      name: '',
      address: '',
      city: '',
      state: '',
      pincode: '',
      phone: '',
      email: '',
      totalRooms: 0,
      upiId: '',
      upiPayeeName: '',
    );
    _properties = [];
    staffName = '';
    staffRole = '';
    staffEmail = '';
    staffPhone = '';
    staffEmployeeId = '';
    _rooms.clear();
    _guests.clear();
    _stays.clear();
    _bills.clear();
    _payments.clear();
    _expenses.clear();
    WhatsAppService.currentHotelId = null;
    notifyListeners();
  }
}
