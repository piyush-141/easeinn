import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/room.dart';
import 'package:mobile/models/stay.dart';
import 'package:mobile/services/hotel_store.dart';

void main() {
  group('HotelStore - Real Dynamic Stats & Lifecycle Invariants', () {
    late HotelStore store;

    setUp(() {
      store = HotelStore();
    });

    test('Initial state metrics are computed from real inventory', () {
      // Real Inventory: 12 rooms seeded (101-106 on Floor 1, 201-206 on Floor 2)
      // All are initialized with real statuses
      expect(store.totalRooms, greaterThan(0));
      expect(store.vacantRooms, equals(store.totalRooms));
      expect(store.occupiedRooms, 0);
      expect(store.cleaningRooms, 0);

      // Occupancy % is strictly 0% when vacant
      expect(store.occupancyRate, 0);

      // Active in-house stays match occupied rooms
      expect(store.activeStays.length, 0);

      // Revenue today is strictly 0.0 initially (no fake stats)
      expect(store.revenueToday, 0.0);
    });

    test('Full Check-In lifecycle updates all stats atomically without fake stats', () {
      final initialTotal = store.totalRooms;
      final initialOccupied = store.occupiedRooms;
      final initialVacant = store.vacantRooms;
      final initialRevenue = store.revenueToday;
      final initialStays = store.activeStays.length;

      // Select available Room 101
      final room101 = store.rooms.firstWhere((r) => r.roomNumber == '101');
      expect(room101.status, RoomStatus.vacant);

      // Execute Check-in with 2 nights @ 2500, paid 2000 advance
      final now = DateTime.now();
      final checkOutDate = now.add(const Duration(days: 2));

      final checkInSummary = store.checkInGuest(
        roomId: room101.id,
        expectedCheckOut: checkOutDate,
        numGuests: 2,
        nightlyRate: 2500.0,
        fullName: 'Rohit Sharma',
        phone: '+91 98765 43210',
        email: 'rohit@example.com',
        idType: 'aadhaar',
        idNumber: '9988 7766 5544',
        dateOfBirth: '1987-04-30',
        gender: 'Male',
        address: 'Sector 14, Gurgaon, Haryana 122001',
        pincode: '122001',
        fatherName: 'G. Sharma',
        advanceAmount: 2000.0,
        paymentMethod: 'upi',
      );

      expect(checkInSummary['stayId'], isNotNull);
      expect(checkInSummary['guestName'], 'Rohit Sharma');
      expect(checkInSummary['roomNumber'], '101');
      expect(checkInSummary['totalAmount'], 5000.0);
      expect(checkInSummary['advancePaid'], 2000.0);

      // Verify room status transitioned to occupied
      final updatedRoom101 = store.rooms.firstWhere((r) => r.roomNumber == '101');
      expect(updatedRoom101.status, RoomStatus.occupied);
      expect(updatedRoom101.currentGuestName, 'Rohit Sharma');

      // Verify occupancy incremented
      expect(store.occupiedRooms, initialOccupied + 1);
      expect(store.vacantRooms, initialVacant - 1);
      expect(store.activeStays.length, initialStays + 1);

      // Verify occupancy rate updated dynamically: (1 / totalRooms) * 100
      final expectedOccupancy = ((initialOccupied + 1) / initialTotal * 100).round();
      expect(store.occupancyRate, expectedOccupancy);

      // Verify revenue increased by exact advance payment amount
      expect(store.revenueToday, initialRevenue + 2000.0);

      // Verify guest record exists in guests list with masked ID
      expect(store.guests.any((g) => g.fullName == 'Rohit Sharma' && g.idNumberMasked.contains('5544')), isTrue);

      // Verify bill folio was generated with correct balance
      final stayId = checkInSummary['stayId'] as String;
      final bill = store.bills.firstWhere((b) => b.stayId == stayId);
      expect(bill.subtotal, 5000.0);
      expect(bill.amountPaid, 2000.0);
      expect(bill.outstanding, 3000.0);
      expect(bill.payments.length, 1);
      expect(bill.payments.first.amount, 2000.0);
    });

    test('Full Check-Out lifecycle transitions room to needs cleaning and settles folio', () {
      // First check-in guest to Room 102
      final room102 = store.rooms.firstWhere((r) => r.roomNumber == '102');
      final checkInSummary = store.checkInGuest(
        roomId: room102.id,
        expectedCheckOut: DateTime.now().add(const Duration(days: 1)),
        numGuests: 1,
        nightlyRate: 3000.0,
        fullName: 'Priya Patel',
        phone: '+91 91234 56789',
        idType: 'pan',
        idNumber: 'ABCDE1234F',
        advanceAmount: 1000.0,
        paymentMethod: 'cash',
      );

      final stayId = checkInSummary['stayId'] as String;
      final initialOccupied = store.occupiedRooms;
      final initialCleaning = store.cleaningRooms;
      final initialRevenue = store.revenueToday;

      // Verify stay is active
      final activeStay = store.activeStays.firstWhere((s) => s.id == stayId);
      expect(activeStay.status, StayStatus.active);

      // Execute Check-out settling remaining balance (3000 - 1000 = 2000)
      final settledBill = store.checkOutGuest(
        stayId: stayId,
        paymentAmount: 2000.0,
        paymentMethod: 'card',
      );

      expect(settledBill.status, 'finalized');
      expect(settledBill.outstanding, 0.0);
      expect(settledBill.amountPaid, 3000.0);

      // Stay is completed
      final stay = store.stays.firstWhere((s) => s.id == stayId);
      expect(stay.status, StayStatus.checkedOut);

      // Room must transition to "needsCleaning"
      final updatedRoom = store.rooms.firstWhere((r) => r.id == room102.id);
      expect(updatedRoom.status, RoomStatus.needsCleaning);

      // Dynamic counts update
      expect(store.occupiedRooms, initialOccupied - 1);
      expect(store.cleaningRooms, initialCleaning + 1);
      expect(store.revenueToday, initialRevenue + 2000.0);
    });

    test('Mark Clean 1-tap action transitions room from cleaning to vacant', () {
      // Set room 103 to needs cleaning
      final room103 = store.rooms.firstWhere((r) => r.roomNumber == '103');
      store.updateRoomStatus(room103.id, RoomStatus.needsCleaning);

      expect(store.rooms.firstWhere((r) => r.id == room103.id).status, RoomStatus.needsCleaning);
      final initialCleaning = store.cleaningRooms;
      final initialVacant = store.vacantRooms;

      store.markRoomClean(room103.id);

      final updatedRoom103 = store.rooms.firstWhere((r) => r.roomNumber == '103');
      expect(updatedRoom103.status, RoomStatus.vacant);
      expect(store.cleaningRooms, initialCleaning - 1);
      expect(store.vacantRooms, initialVacant + 1);
    });

    test('Multi-property addition and switching maintains isolated dynamic states', () {
      expect(store.properties.length, 1);

      store.addNewProperty(
        name: 'EaseInn Resort & Spa',
        address: 'Candolim Beach Road',
        city: 'Goa',
        state: 'Goa',
        phone: '+91 832 248 9000',
        email: 'goa@easeinn.com',
        totalRooms: 20,
      );

      expect(store.properties.length, 2);
      final newProp = store.properties.last;
      expect(newProp.name, 'EaseInn Resort & Spa');
      expect(store.currentProperty.id, newProp.id);

      // Verify new property initialized fresh inventory
      expect(store.totalRooms, 12);
      expect(store.occupiedRooms, 0);
    });
  });
}
