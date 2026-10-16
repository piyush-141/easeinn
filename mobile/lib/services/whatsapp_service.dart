import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'ocr_service.dart';

class WhatsAppService {
  static String get baseUrl => OcrService.baseUrl;

  /// Trigger automated Check-in Welcome WhatsApp message
  static Future<bool> triggerCheckIn({
    required String guestName,
    required String phone,
    required String hotelName,
    required String roomNumber,
    required String checkInDate,
    required String checkOutDate,
    String? stayId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/hook/checkin');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'guestName': guestName,
          'phone': phone,
          'hotelName': hotelName,
          'roomNumber': roomNumber,
          'checkInDate': checkInDate,
          'checkOutDate': checkOutDate,
          'stayId': stayId,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('[WhatsAppService] Error triggering check-in notification: $e');
      return false;
    }
  }

  /// Trigger automated Checkout Thank-You WhatsApp message
  static Future<bool> triggerCheckOut({
    required String guestName,
    required String phone,
    required String hotelName,
    required String roomNumber,
    required String checkInDate,
    required String checkOutDate,
    String? stayId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/hook/checkout');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'guestName': guestName,
          'phone': phone,
          'hotelName': hotelName,
          'roomNumber': roomNumber,
          'checkInDate': checkInDate,
          'checkOutDate': checkOutDate,
          'stayId': stayId,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('[WhatsAppService] Error triggering check-out notification: $e');
      return false;
    }
  }

  /// Trigger automated Booking Confirmation WhatsApp message
  static Future<bool> triggerReservation({
    required String guestName,
    required String phone,
    required String hotelName,
    required String roomNumber,
    required String checkInDate,
    required String checkOutDate,
    String? stayId,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/hook/reservation');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'guestName': guestName,
          'phone': phone,
          'hotelName': hotelName,
          'roomNumber': roomNumber,
          'checkInDate': checkInDate,
          'checkOutDate': checkOutDate,
          'stayId': stayId,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint('[WhatsAppService] Error triggering reservation notification: $e');
      return false;
    }
  }
}
