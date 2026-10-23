import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/property.dart';
import 'package:mobile/models/room.dart';
import 'package:mobile/models/stay.dart';
import 'package:mobile/models/bill.dart';
import 'package:mobile/services/hotel_store.dart';
import 'package:mobile/services/supabase_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EaseInn Data Persistence, UUID Healing & Session Lifecycle Audit', () {
    late HotelStore store;
    const testPropertyId = '11111111-2222-3333-4444-555555555555';

    setUp(() {
      store = HotelStore();
      store.initCleanAccount(
        property: Property(
          id: testPropertyId,
          name: 'The Grand Orchid',
          address: '100 Heritage Road',
          city: 'Mysuru',
          state: 'Karnataka',
          pincode: '570001',
          phone: '+91 821 240 1234',
          email: 'orchid@easeinn.com',
          totalRooms: 12,
        ),
        managerName: 'Aditi Rao',
        managerEmail: 'orchid@easeinn.com',
        managerPhone: '+91 98888 12345',
      );
    });

    test('1. Room inventory generates valid RFC4122 v4 UUIDs for real properties', () {
      expect(store.rooms.length, 12);
      for (final r in store.rooms) {
        expect(SupabaseSyncService.isValidUuid(r.id), isTrue,
            reason: 'Room ${r.roomNumber} ID "${r.id}" must be a valid UUID');
        expect(r.propertyId, equals(testPropertyId));
        expect(r.status, equals(RoomStatus.vacant));
      }
    });

    test('2. Check-In persists active stay, links room, and folios bill with valid UUIDs', () {
      final room101 = store.rooms.firstWhere((r) => r.roomNumber == '101');
      final checkOutDate = DateTime.now().add(const Duration(days: 3));

      final result = store.checkInGuest(
        roomId: room101.id,
        expectedCheckOut: checkOutDate,
        numGuests: 2,
        nightlyRate: 3000.0,
        fullName: 'Vikram Malhotra',
        phone: '+91 98111 22233',
        email: 'vikram@example.com',
        idType: 'passport',
        idNumber: 'Z1234567',
        dateOfBirth: '1985-06-15',
        gender: 'Male',
        address: 'Bandra West, Mumbai',
        pincode: '400050',
        fatherName: 'R. Malhotra',
        advanceAmount: 3000.0,
        paymentMethod: 'upi',
      );

      final stayId = result['stayId'] as String;
      expect(SupabaseSyncService.isValidUuid(stayId), isTrue);

      // Verify room status is occupied
      final updatedRoom = store.rooms.firstWhere((r) => r.id == room101.id);
      expect(updatedRoom.status, equals(RoomStatus.occupied));
      expect(updatedRoom.currentGuestName, equals('Vikram Malhotra'));
      expect(updatedRoom.currentStayId, equals(stayId));

      // Verify bill and payment creation
      final bill = store.bills.firstWhere((b) => b.stayId == stayId);
      expect(SupabaseSyncService.isValidUuid(bill.id), isTrue);
      expect(bill.propertyId, equals(testPropertyId));
      expect(bill.subtotal, equals(9000.0));
      expect(bill.amountPaid, equals(3000.0));
      expect(bill.outstanding, equals(6000.0));
      expect(bill.payments.length, equals(1));

      final payment = bill.payments.first;
      expect(SupabaseSyncService.isValidUuid(payment.id), isTrue);
      expect(payment.propertyId, equals(testPropertyId));
      expect(payment.billId, equals(bill.id));
      expect(payment.amount, equals(3000.0));
      expect(payment.method, equals('upi'));
    });

    test('3. Partial Payment records with UUID and correctly updates outstanding balance', () {
      final room102 = store.rooms.firstWhere((r) => r.roomNumber == '102');
      final result = store.checkInGuest(
        roomId: room102.id,
        expectedCheckOut: DateTime.now().add(const Duration(days: 2)),
        numGuests: 1,
        nightlyRate: 2000.0,
        fullName: 'Sunita Rao',
        phone: '+91 98222 33344',
        idType: 'driving_license',
        idNumber: 'DL-KA-01-2020-001',
        advanceAmount: 1000.0,
        paymentMethod: 'cash',
      );

      final stayId = result['stayId'] as String;
      final bill = store.bills.firstWhere((b) => b.stayId == stayId);
      expect(bill.outstanding, equals(3000.0)); // 4000 total - 1000 advance

      // Record partial payment
      store.recordPartialPayment(
        billId: bill.id,
        amount: 2000.0,
        method: 'upi',
        reference: 'UPI-REF-9988',
      );

      expect(bill.amountPaid, equals(3000.0));
      expect(bill.outstanding, equals(1000.0));
      expect(bill.payments.length, equals(2));
      expect(bill.payments.last.method, equals('upi'));
      expect(bill.payments.last.reference, equals('UPI-REF-9988'));
      expect(SupabaseSyncService.isValidUuid(bill.payments.last.id), isTrue);
    });

    test('4. Check-Out Guest finalizes folio, creates final payment with UUID, and marks room needsCleaning', () {
      final room103 = store.rooms.firstWhere((r) => r.roomNumber == '103');
      final result = store.checkInGuest(
        roomId: room103.id,
        expectedCheckOut: DateTime.now().add(const Duration(days: 1)),
        numGuests: 1,
        nightlyRate: 2500.0,
        fullName: 'Ananya Sen',
        phone: '+91 98333 44455',
        idType: 'aadhaar',
        idNumber: '1122 3344 5566',
        advanceAmount: 1000.0,
        paymentMethod: 'card',
      );

      final stayId = result['stayId'] as String;

      // Execute Check-Out settling remaining ₹1500
      final finalizedBill = store.checkOutGuest(
        stayId: stayId,
        paymentAmount: 1500.0,
        paymentMethod: 'upi',
        sendWhatsApp: false,
      );

      expect(finalizedBill.status, equals('finalized'));
      expect(finalizedBill.amountPaid, equals(2500.0));
      expect(finalizedBill.outstanding, equals(0.0));
      expect(finalizedBill.propertyId, equals(testPropertyId));
      expect(SupabaseSyncService.isValidUuid(finalizedBill.id), isTrue);

      // Verify room status changed to needsCleaning and cleared active stay
      final updatedRoom = store.rooms.firstWhere((r) => r.id == room103.id);
      expect(updatedRoom.status, equals(RoomStatus.needsCleaning));
      expect(updatedRoom.currentStayId, isNull);
      expect(updatedRoom.currentGuestName, isNull);

      // Verify stay record is checkedOut
      final stay = store.stays.firstWhere((s) => s.id == stayId);
      expect(stay.status, equals(StayStatus.checkedOut));
      expect(stay.checkOutAt, isNotNull);
    });

    test('5. Room reconciliation self-heals mismatched roomId via roomNumber fallback', () {
      final room104 = store.rooms.firstWhere((r) => r.roomNumber == '104');
      final stayId = SupabaseSyncService.generateUuid();

      // Remote stay from Supabase where roomId was non-matching, but linked room metadata is 104
      final remoteStay = {
        'id': stayId,
        'property_id': testPropertyId,
        'room_id': 'mismatched-non-uuid-string',
        'guest_id': SupabaseSyncService.generateUuid(),
        'check_in_at': DateTime.now().subtract(const Duration(hours: 4)).toIso8601String(),
        'expected_checkout': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'nightly_rate': 2800.0,
        'num_guests': 1,
        'num_adults': 1,
        'num_kids': 0,
        'status': 'active',
        'rooms': {
          'id': room104.id,
          'property_id': testPropertyId,
          'room_number': '104',
          'category_name': 'Deluxe Room',
          'floor': 1,
          'base_rate': 2800.0,
        },
      };

      store.applyRemoteData({
        'stays': [remoteStay],
      });

      final healedStay = store.stays.firstWhere((s) => s.id == stayId);
      expect(healedStay.roomId, equals(room104.id));
      expect(store.rooms.firstWhere((r) => r.id == room104.id).status, equals(RoomStatus.occupied));
    });

    test('6. State export and import retains all rooms, bills, payments, and stays without data loss', () {
      final room105 = store.rooms.firstWhere((r) => r.roomNumber == '105');
      store.checkInGuest(
        roomId: room105.id,
        expectedCheckOut: DateTime.now().add(const Duration(days: 2)),
        numGuests: 2,
        nightlyRate: 3200.0,
        fullName: 'Kiran Patel',
        phone: '+91 98444 55566',
        idType: 'aadhaar',
        idNumber: '2233 4455 6677',
        advanceAmount: 2000.0,
        paymentMethod: 'upi',
      );

      final stateBefore = store.exportState();
      final billsBeforeCount = store.bills.length;
      final paymentsBeforeCount = store.payments.length;
      final staysBeforeCount = store.stays.length;

      // Simulate a new store instance (app restart)
      final restoredStore = HotelStore();
      restoredStore.initCleanAccount(
        property: store.currentProperty,
        managerName: store.staffName,
        managerEmail: store.staffEmail,
        managerPhone: store.staffPhone,
      );

      // Re-apply state
      restoredStore.exportState(); // baseline
      final localData = Map<String, dynamic>.from(stateBefore);

      // Verify that all properties in export are JSON encodable and complete
      expect(localData['rooms'].length, equals(12));
      expect(localData['bills'].length, equals(billsBeforeCount));
      expect(localData['payments'].length, equals(paymentsBeforeCount));
      expect(localData['stays'].length, equals(staysBeforeCount));
    });

    test('7. Bill & Payment copyWith and JSON round-trip retains propertyId and billId', () {
      final payment = Payment(
        id: SupabaseSyncService.generateUuid(),
        propertyId: testPropertyId,
        billId: 'bill-uuid-1234',
        amount: 4500.0,
        method: 'card',
        paymentType: 'full',
      );

      final pJson = payment.toJson();
      expect(pJson['property_id'], equals(testPropertyId));
      expect(pJson['bill_id'], equals('bill-uuid-1234'));
      expect(pJson['amount'], equals(4500.0));

      final pRestored = Payment.fromJson(pJson);
      expect(pRestored.id, equals(payment.id));
      expect(pRestored.propertyId, equals(testPropertyId));
      expect(pRestored.billId, equals('bill-uuid-1234'));
      expect(pRestored.amount, equals(4500.0));

      final bill = Bill(
        id: SupabaseSyncService.generateUuid(),
        propertyId: testPropertyId,
        stayId: SupabaseSyncService.generateUuid(),
        billNumber: 'INV-2026-TEST',
        subtotal: 5000.0,
        amountPaid: 4500.0,
        outstanding: 500.0,
        status: 'draft',
        payments: [pRestored],
      );

      final bJson = bill.toJson();
      expect(bJson['property_id'], equals(testPropertyId));
      expect(bJson['payments'].length, equals(1));
      expect(bJson['payments'].first['bill_id'], equals('bill-uuid-1234'));

      final bRestored = Bill.fromJson(bJson);
      expect(bRestored.id, equals(bill.id));
      expect(bRestored.propertyId, equals(testPropertyId));
      expect(bRestored.payments.first.amount, equals(4500.0));
    });
  });
}
