import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/property.dart';
import '../models/room.dart';
import '../models/guest.dart';
import '../models/stay.dart';
import '../models/bill.dart';
import '../models/expense.dart';
import 'supabase_service.dart';

class SupabaseSyncService {
  /// Generate standard RFC 4122 v4 UUID for database primary keys
  static String generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // Version 4
    values[8] = (values[8] & 0x3f) | 0x80; // Variant 10
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Check if a string is a valid UUID
  static bool isValidUuid(String? id) {
    if (id == null) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id);
  }

  static SupabaseClient? get _client => SupabaseConfig.client;

  /// Ensures an active Supabase session with a valid, non-expired JWT.
  /// Refreshes expired sessions automatically.
  static Future<bool> ensureSession() async {
    final client = _client;
    if (client == null) return false;
    try {
      final session = client.auth.currentSession;
      if (session == null) return false;
      if (session.isExpired) {
        debugPrint('[SupabaseSync] Session expired, refreshing token...');
        final res = await client.auth.refreshSession();
        final refreshed = res.session != null;
        debugPrint('[SupabaseSync] Session refresh result: $refreshed');
        return refreshed;
      }
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Session validation error: $e');
      return false;
    }
  }

  /// Sync hotel property details to Supabase
  static Future<bool> syncProperty(Property property) async {
    final client = _client;
    if (client == null || !isValidUuid(property.id)) return false;
    await ensureSession();

    try {
      await client.from('properties').upsert({
        'id': property.id,
        'name': property.name,
        'address': property.address,
        'city': property.city,
        'state': property.state,
        'pincode': property.pincode,
        'phone': property.phone,
        'email': property.email,
        'gst_number': property.gstNumber,
        'upi_id': property.upiId,
        'upi_payee_name': property.upiPayeeName,
        'currency': 'INR',
        'timezone': 'Asia/Kolkata',
      }, onConflict: 'id');
      debugPrint('[SupabaseSync] Property synced: ${property.name} (${property.id})');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Property sync error: $e');
      return false;
    }
  }

  /// Sync rooms list to Supabase and return the authoritative map of room_number -> room UUID
  static Future<Map<String, String>> syncRooms(String propertyId, List<Room> rooms) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return {};
    await ensureSession();

    try {
      final propertyRooms = rooms.where((r) => r.propertyId == propertyId).toList();
      if (propertyRooms.isEmpty) return {};

      final rows = propertyRooms.map((r) {
        final roomId = isValidUuid(r.id) ? r.id : generateUuid();
        return {
          'id': roomId,
          'property_id': propertyId,
          'room_number': r.roomNumber,
          'floor': r.floor,
          'status': r.status.dbValue,
          'base_rate': r.baseRate,
          'category_name': r.categoryName,
          'is_active': true,
        };
      }).toList();

      final res = await client.from('rooms').upsert(
        rows,
        onConflict: 'property_id, room_number',
      ).select('id, room_number');

      final mapping = <String, String>{};
      for (final row in res) {
        final numStr = row['room_number']?.toString();
        final idStr = row['id']?.toString();
        if (numStr != null && idStr != null) {
          mapping[numStr] = idStr;
        }
      }
      debugPrint('[SupabaseSync] Synced ${propertyRooms.length} rooms, mapped ${mapping.length} IDs');
      return mapping;
    } catch (e) {
      debugPrint('[SupabaseSync] Rooms sync error: $e');
      return {};
    }
  }

  /// Sync a single room status to Supabase
  static Future<bool> updateRoomStatus(String propertyId, String roomNumber, RoomStatus status) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return false;
    await ensureSession();

    try {
      await client
          .from('rooms')
          .update({'status': status.dbValue})
          .eq('property_id', propertyId)
          .eq('room_number', roomNumber);
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Room status update error: $e');
      return false;
    }
  }

  /// Delete a room from Supabase
  static Future<bool> deleteRoom(String propertyId, String roomId) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId) || !isValidUuid(roomId)) return false;
    await ensureSession();

    try {
      await client.from('rooms').delete().eq('property_id', propertyId).eq('id', roomId);
      debugPrint('[SupabaseSync] Deleted room $roomId from property $propertyId');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Room delete error: $e');
      return false;
    }
  }

  /// Sync guest to Supabase
  static Future<bool> syncGuest(Guest guest) async {
    final client = _client;
    if (client == null || !isValidUuid(guest.propertyId)) return false;
    await ensureSession();

    try {
      final guestId = isValidUuid(guest.id) ? guest.id : generateUuid();
      final genderNormalized = guest.gender?.trim().toLowerCase();
      final validGenders = {'male', 'female', 'other'};
      final finalGender = (genderNormalized != null && validGenders.contains(genderNormalized))
          ? genderNormalized
          : null;

      await client.from('guests').upsert({
        'id': guestId,
        'property_id': guest.propertyId,
        'full_name': guest.fullName,
        'phone': guest.phone,
        'email': guest.email,
        'id_type': guest.idType,
        'id_number_masked': guest.idNumberMasked,
        'id_number': guest.idNumber,
        'date_of_birth': guest.dateOfBirth,
        'gender': finalGender,
        'address': guest.address,
        'pincode': guest.pincode,
        'father_name': guest.fatherName,
        'notes': guest.notes,
        'stays_count': guest.staysCount,
        'created_at': guest.createdAt.toIso8601String(),
      }, onConflict: 'id');
      debugPrint('[SupabaseSync] Guest synced: ${guest.fullName} ($guestId)');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Guest sync error: $e');
      return false;
    }
  }

  /// Sync stay to Supabase (with automatic room ID healing from knownRooms)
  static Future<bool> syncStay(Stay stay, {List<Room>? knownRooms}) async {
    final client = _client;
    if (client == null || !isValidUuid(stay.propertyId)) return false;
    if (!isValidUuid(stay.guestId)) return false;
    await ensureSession();

    // Heal room ID if needed using knownRooms
    String effectiveRoomId = stay.roomId;
    if (!isValidUuid(effectiveRoomId) && knownRooms != null) {
      final match = knownRooms.where(
        (r) => r.id == stay.roomId || r.roomNumber == stay.room?.roomNumber,
      ).firstOrNull;
      if (match != null && isValidUuid(match.id)) {
        effectiveRoomId = match.id;
        stay.roomId = match.id;
      }
    }

    try {
      final stayId = isValidUuid(stay.id) ? stay.id : generateUuid();

      String statusStr;
      switch (stay.status) {
        case StayStatus.checkedOut:
          statusStr = 'checked_out';
          break;
        case StayStatus.reserved:
          statusStr = 'reserved';
          break;
        case StayStatus.active:
          statusStr = 'active';
          break;
      }

      await client.from('stays').upsert({
        'id': stayId,
        'property_id': stay.propertyId,
        'guest_id': stay.guestId,
        'room_id': isValidUuid(effectiveRoomId) ? effectiveRoomId : null,
        'check_in_at': stay.checkInAt.toIso8601String(),
        if (stay.checkOutAt != null) 'check_out_at': stay.checkOutAt!.toIso8601String(),
        'expected_checkout': stay.expectedCheckOut.toIso8601String(),
        'nightly_rate': stay.nightlyRate,
        'num_guests': stay.numGuests,
        'num_adults': stay.numAdults,
        'num_kids': stay.numKids,
        'status': statusStr,
      }, onConflict: 'id');

      // Sync co-guests and stay_guests link
      if (stay.coGuests.isNotEmpty) {
        for (final cg in stay.coGuests) {
          await syncGuest(cg);
          if (isValidUuid(cg.id)) {
            try {
              await client.from('stay_guests').upsert({
                'stay_id': stayId,
                'guest_id': cg.id,
              }, onConflict: 'stay_id, guest_id');
            } catch (sgErr) {
              debugPrint('[SupabaseSync] stay_guest link notice: $sgErr');
            }
          }
        }
      }

      debugPrint('[SupabaseSync] Stay synced: $stayId (Status: $statusStr, Room: $effectiveRoomId)');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Stay sync error: $e');
      return false;
    }
  }

  /// Delete a stay from Supabase (e.g. on reservation cancellation)
  static Future<bool> deleteStay(String stayId) async {
    final client = _client;
    if (client == null || !isValidUuid(stayId)) return false;
    await ensureSession();

    try {
      await client.from('stays').delete().eq('id', stayId);
      debugPrint('[SupabaseSync] Stay deleted: $stayId');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Stay delete error: $e');
      return false;
    }
  }

  /// Upsert a bill, its line items, and associated payments to Supabase
  static Future<bool> syncBill(Bill bill, [String? propertyId]) async {
    final client = _client;
    final propId = (propertyId != null && propertyId.isNotEmpty) ? propertyId : bill.propertyId;
    if (client == null || !isValidUuid(propId)) return false;
    final stayId = isValidUuid(bill.stayId) ? bill.stayId : null;
    if (stayId == null) return false;
    await ensureSession();

    try {
      final billId = isValidUuid(bill.id) ? bill.id : generateUuid();

      String status = bill.status;
      if (status != 'draft' && status != 'finalized' && status != 'void' && status != 'reserved') {
        status = 'draft';
      }

      await client.from('bills').upsert({
        'id': billId,
        'property_id': propId,
        'stay_id': stayId,
        'bill_number': bill.billNumber,
        'subtotal': bill.subtotal,
        'tax_amount': 0.0,
        'discount_amount': 0.0,
        'total': bill.subtotal,
        'amount_paid': bill.amountPaid,
        'outstanding': bill.outstanding,
        'status': status,
        'created_at': bill.createdAt.toIso8601String(),
      }, onConflict: 'id');

      // Sync line items
      for (final li in bill.lineItems) {
        final liId = isValidUuid(li.id) ? li.id : generateUuid();
        try {
          await client.from('bill_line_items').upsert({
            'id': liId,
            'bill_id': billId,
            'description': li.description,
            'quantity': li.quantity,
            'unit_price': li.unitPrice,
            'amount': li.amount,
            'item_type': 'room_charge',
          }, onConflict: 'id');
        } catch (liErr) {
          debugPrint('[SupabaseSync] Line item upsert notice: $liErr');
        }
      }

      // Sync payments attached to this bill
      for (final p in bill.payments) {
        await syncPayment(p, billId, propId);
      }

      debugPrint('[SupabaseSync] Bill synced: ${bill.billNumber} ($billId)');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Bill sync error: $e');
      return false;
    }
  }

  /// Delete a bill from Supabase
  static Future<bool> deleteBill(String billId) async {
    final client = _client;
    if (client == null || !isValidUuid(billId)) return false;
    await ensureSession();

    try {
      await client.from('bills').delete().eq('id', billId);
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Bill delete error: $e');
      return false;
    }
  }

  /// Upsert a payment to Supabase
  static Future<bool> syncPayment(Payment payment, [String? billId, String? propertyId]) async {
    final client = _client;
    final propId = (propertyId != null && propertyId.isNotEmpty) ? propertyId : payment.propertyId;
    final bId = (billId != null && billId.isNotEmpty) ? billId : payment.billId;
    if (client == null || propId == null || !isValidUuid(propId) || bId == null || !isValidUuid(bId)) return false;
    await ensureSession();

    try {
      final payId = isValidUuid(payment.id) ? payment.id : generateUuid();
      final validMethods = {'cash', 'upi', 'card', 'bank_transfer', 'other'};
      final method = validMethods.contains(payment.method.toLowerCase())
          ? payment.method.toLowerCase()
          : 'cash';

      final validTypes = {'advance', 'partial', 'full', 'refund'};
      final paymentType = validTypes.contains(payment.paymentType.toLowerCase())
          ? payment.paymentType.toLowerCase()
          : 'advance';

      await client.from('payments').upsert({
        'id': payId,
        'property_id': propId,
        'bill_id': bId,
        'amount': payment.amount,
        'method': method,
        'payment_type': paymentType,
        'reference': payment.reference,
        'recorded_at': payment.recordedAt.toIso8601String(),
        'is_void': false,
      }, onConflict: 'id');

      debugPrint('[SupabaseSync] Payment synced: ₹${payment.amount} ($payId)');
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Payment sync error: $e');
      return false;
    }
  }

  /// Upsert a single expense to Supabase
  static Future<void> syncExpense(Expense expense) async {
    final client = _client;
    if (client == null || !isValidUuid(expense.id)) return;
    await ensureSession();

    try {
      await client.from('expenses').upsert({
        'id': expense.id,
        'property_id': expense.propertyId,
        'amount': expense.amount,
        'category': expense.category,
        'payment_method': expense.paymentMethod,
        'reference': expense.reference,
        'notes': expense.notes,
        'added_by': expense.addedBy,
        'recorded_at': expense.recordedAt.toIso8601String(),
      }, onConflict: 'id');
      debugPrint('[SupabaseSync] Expense synced: ₹${expense.amount} (${expense.category})');
    } catch (e) {
      debugPrint('[SupabaseSync] syncExpense error: $e');
    }
  }

  /// Delete an expense from Supabase
  static Future<void> deleteExpense(String expenseId) async {
    final client = _client;
    if (client == null || !isValidUuid(expenseId)) return;
    await ensureSession();

    try {
      await client.from('expenses').delete().eq('id', expenseId);
      debugPrint('[SupabaseSync] Expense deleted: $expenseId');
    } catch (e) {
      debugPrint('[SupabaseSync] deleteExpense error: $e');
    }
  }

  /// Pull expenses for a property from Supabase
  static Future<List<Map<String, dynamic>>> pullExpenses(String propertyId) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return [];
    await ensureSession();

    try {
      final res = await client
          .from('expenses')
          .select('*')
          .eq('property_id', propertyId)
          .order('recorded_at', ascending: false);
      return res;
    } catch (e) {
      debugPrint('[SupabaseSync] pullExpenses notice: $e');
      return [];
    }
  }

  /// Pull full remote dataset for property from Supabase.
  /// Returns null if not configured, network fails, or session is unauthenticated.
  /// Never returns a false empty map on errors.
  static Future<Map<String, dynamic>?> pullRemoteData(String propertyId) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return null;

    final sessionOk = await ensureSession();
    if (!sessionOk) {
      debugPrint('[SupabaseSync] pullRemoteData aborted: no active valid session');
      return null;
    }

    try {
      final results = await Future.wait([
        client.from('rooms').select('*').eq('property_id', propertyId).order('room_number'),
        client.from('guests').select('*').eq('property_id', propertyId).order('created_at', ascending: false),
        client.from('stays').select('*').eq('property_id', propertyId).order('check_in_at', ascending: false),
        client.from('expenses').select('*').eq('property_id', propertyId).order('recorded_at', ascending: false).catchError((_) => []),
        client.from('bills').select('*').eq('property_id', propertyId).order('created_at', ascending: false).catchError((_) => []),
        client.from('payments').select('*').eq('property_id', propertyId).order('recorded_at', ascending: false).catchError((_) => []),
      ]);

      final roomsData = results[0] as List<dynamic>? ?? [];
      final guestsData = results[1] as List<dynamic>? ?? [];
      final staysData = results[2] as List<dynamic>? ?? [];
      final expensesData = results[3] as List<dynamic>? ?? [];
      final billsData = results[4] as List<dynamic>? ?? [];
      final paymentsData = results[5] as List<dynamic>? ?? [];

      // Map payments by bill_id
      final paymentsByBill = <String, List<Map<String, dynamic>>>{};
      for (final p in paymentsData) {
        if (p is Map<String, dynamic>) {
          final bId = p['bill_id']?.toString();
          if (bId != null) {
            paymentsByBill.putIfAbsent(bId, () => []).add(p);
          }
        }
      }

      // Fetch line items for bills
      final billIds = billsData
          .map((b) => b['id']?.toString())
          .whereType<String>()
          .where((id) => isValidUuid(id))
          .toList();

      final lineItemsByBill = <String, List<Map<String, dynamic>>>{};
      if (billIds.isNotEmpty) {
        try {
          final lineItemsRes = await client
              .from('bill_line_items')
              .select('*')
              .inFilter('bill_id', billIds);
          for (final li in lineItemsRes) {
            final bId = li['bill_id']?.toString();
            if (bId != null) {
              lineItemsByBill.putIfAbsent(bId, () => []).add(li);
            }
          }
        } catch (liErr) {
          debugPrint('[SupabaseSync] Line items fetch notice: $liErr');
        }
      }

      // Enrich bills with their line items and payments
      final enrichedBills = billsData.map((b) {
        if (b is! Map<String, dynamic>) return b;
        final enriched = Map<String, dynamic>.from(b);
        final bId = enriched['id']?.toString() ?? '';
        enriched['line_items'] = lineItemsByBill[bId] ?? [];
        enriched['payments'] = paymentsByBill[bId] ?? [];
        return enriched;
      }).toList();

      // Guest and Room Maps for Stays lookup
      final guestMap = <String, Map<String, dynamic>>{};
      for (final g in guestsData) {
        if (g is Map<String, dynamic>) {
          final id = g['id']?.toString();
          if (id != null) guestMap[id] = g;
        }
      }

      final roomMap = <String, Map<String, dynamic>>{};
      for (final r in roomsData) {
        if (r is Map<String, dynamic>) {
          final id = r['id']?.toString();
          if (id != null) roomMap[id] = r;
        }
      }

      // Enrich stays
      final enrichedStays = staysData.map((s) {
        if (s is! Map<String, dynamic>) return s;
        final enriched = Map<String, dynamic>.from(s);
        final guestId = enriched['guest_id']?.toString();
        final roomId = enriched['room_id']?.toString();
        if (guestId != null && guestMap.containsKey(guestId)) {
          enriched['guest'] = guestMap[guestId];
        }
        if (roomId != null && roomMap.containsKey(roomId)) {
          enriched['room'] = roomMap[roomId];
        }
        return enriched;
      }).toList();

      debugPrint('[SupabaseSync] Pull remote completed: ${roomsData.length} rooms, ${guestsData.length} guests, ${staysData.length} stays, ${enrichedBills.length} bills, ${expensesData.length} expenses');

      return {
        'rooms': roomsData,
        'guests': guestsData,
        'stays': enrichedStays,
        'expenses': expensesData,
        'bills': enrichedBills,
        'payments': paymentsData,
      };
    } catch (e) {
      debugPrint('[SupabaseSync] Pull remote data error: $e');
      return null;
    }
  }

  /// Push all pending local data (rooms + guests + stays + bills + expenses) to Supabase in one pass
  static Future<void> pushAllData({
    required Property property,
    required List<Room> rooms,
    required List<Guest> guests,
    required List<Stay> stays,
    List<Bill>? bills,
    List<Expense>? expenses,
  }) async {
    if (!isValidUuid(property.id)) return;
    await ensureSession();

    try {
      await syncProperty(property);
      final roomMapping = await syncRooms(property.id, rooms);

      for (final g in guests) {
        if (g.propertyId == property.id) {
          await syncGuest(g);
        }
      }

      for (final s in stays) {
        if (s.propertyId == property.id) {
          // If stay room ID is not UUID, map from roomMapping
          if (!isValidUuid(s.roomId) && s.room != null) {
            final uuid = roomMapping[s.room!.roomNumber];
            if (uuid != null) s.roomId = uuid;
          }
          await syncStay(s, knownRooms: rooms);
        }
      }

      if (bills != null) {
        for (final b in bills) {
          await syncBill(b, property.id);
        }
      }

      if (expenses != null) {
        for (final e in expenses) {
          if (e.propertyId == property.id) {
            await syncExpense(e);
          }
        }
      }
      debugPrint('[SupabaseSync] Full push completed successfully.');
    } catch (e) {
      debugPrint('[SupabaseSync] pushAllData error: $e');
    }
  }
}
