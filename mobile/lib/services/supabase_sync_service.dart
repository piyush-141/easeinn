import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/property.dart';
import '../models/room.dart';
import '../models/guest.dart';
import '../models/stay.dart';
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

  /// Sync hotel property details to Supabase
  static Future<bool> syncProperty(Property property) async {
    final client = _client;
    if (client == null || !isValidUuid(property.id)) return false;

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
        'currency': 'INR',
        'timezone': 'Asia/Kolkata',
      });
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Property sync notice: $e');
      return false;
    }
  }

  /// Sync rooms list to Supabase
  static Future<bool> syncRooms(String propertyId, List<Room> rooms) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return false;

    try {
      final rows = rooms.map((r) {
        final roomId = isValidUuid(r.id) ? r.id : generateUuid();
        return {
          'id': roomId,
          'property_id': propertyId,
          'room_number': r.roomNumber,
          'floor': r.floor,
          'status': r.status.dbValue,
          'base_rate': r.baseRate,
          'is_active': true,
        };
      }).toList();

      await client.from('rooms').upsert(
        rows,
        onConflict: 'property_id, room_number',
      );
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Rooms sync notice: $e');
      return false;
    }
  }

  /// Sync a single room status to Supabase
  static Future<bool> updateRoomStatus(String propertyId, String roomNumber, RoomStatus status) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return false;

    try {
      await client
          .from('rooms')
          .update({'status': status.dbValue})
          .eq('property_id', propertyId)
          .eq('room_number', roomNumber);
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Room status update notice: $e');
      return false;
    }
  }

  /// Sync guest to Supabase
  static Future<bool> syncGuest(Guest guest) async {
    final client = _client;
    if (client == null || !isValidUuid(guest.propertyId)) return false;

    try {
      final guestId = isValidUuid(guest.id) ? guest.id : generateUuid();
      await client.from('guests').upsert({
        'id': guestId,
        'property_id': guest.propertyId,
        'full_name': guest.fullName,
        'phone': guest.phone,
        'email': guest.email,
        'id_type': guest.idType,
        'id_number_masked': guest.idNumberMasked,
        'date_of_birth': guest.dateOfBirth,
        'gender': guest.gender,
        'address': guest.address,
        'pincode': guest.pincode,
        'notes': guest.notes,
        'created_at': guest.createdAt.toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Guest sync notice: $e');
      return false;
    }
  }

  /// Sync stay to Supabase
  static Future<bool> syncStay(Stay stay) async {
    final client = _client;
    if (client == null || !isValidUuid(stay.propertyId)) return false;

    try {
      final stayId = isValidUuid(stay.id) ? stay.id : generateUuid();
      final guestId = isValidUuid(stay.guestId) ? stay.guestId : generateUuid();

      await client.from('stays').upsert({
        'id': stayId,
        'property_id': stay.propertyId,
        'guest_id': guestId,
        'room_id': isValidUuid(stay.roomId) ? stay.roomId : null,
        'check_in_at': stay.checkInAt.toIso8601String(),
        if (stay.checkOutAt != null) 'check_out_at': stay.checkOutAt!.toIso8601String(),
        'expected_checkout': stay.expectedCheckOut.toIso8601String(),
        'nightly_rate': stay.nightlyRate,
        'status': stay.status == StayStatus.checkedOut
            ? 'checked_out'
            : stay.status == StayStatus.reserved
                ? 'reserved'
                : 'active',
      });
      return true;
    } catch (e) {
      debugPrint('[SupabaseSync] Stay sync notice: $e');
      return false;
    }
  }

  /// Pull full remote dataset for property from Supabase
  static Future<Map<String, dynamic>?> pullRemoteData(String propertyId) async {
    final client = _client;
    if (client == null || !isValidUuid(propertyId)) return null;

    try {
      final results = await Future.wait([
        client.from('rooms').select('*').eq('property_id', propertyId).order('room_number'),
        client.from('guests').select('*').eq('property_id', propertyId).order('created_at', ascending: false),
        client.from('stays').select('*, guests(*)').eq('property_id', propertyId).order('check_in_at', ascending: false),
      ]);

      final roomsData = results[0] as List<dynamic>? ?? [];
      final guestsData = results[1] as List<dynamic>? ?? [];
      final staysData = results[2] as List<dynamic>? ?? [];

      return {
        'rooms': roomsData,
        'guests': guestsData,
        'stays': staysData,
      };
    } catch (e) {
      debugPrint('[SupabaseSync] Pull remote data notice: $e');
      return null;
    }
  }
}
