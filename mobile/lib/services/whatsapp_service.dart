import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhatsAppStatusData {
  final bool success;
  final String status; // 'DISCONNECTED' | 'QR_READY' | 'AUTHENTICATING' | 'READY'
  final bool isConnected;
  final bool isReady;
  final String? qrCodeDataUrl;
  final bool hasActiveQr;
  final String? connectedNumber;
  final String? connectedPushname;
  final int activeTemplatesCount;
  final int totalTemplatesCount;
  final String? initializationError;

  WhatsAppStatusData({
    required this.success,
    required this.status,
    required this.isConnected,
    required this.isReady,
    this.qrCodeDataUrl,
    required this.hasActiveQr,
    this.connectedNumber,
    this.connectedPushname,
    required this.activeTemplatesCount,
    required this.totalTemplatesCount,
    this.initializationError,
  });

  factory WhatsAppStatusData.fromJson(Map<String, dynamic> json) {
    return WhatsAppStatusData(
      success: json['success'] ?? false,
      status: json['status'] ?? 'DISCONNECTED',
      isConnected: json['isConnected'] ?? false,
      isReady: json['isReady'] ?? false,
      qrCodeDataUrl: json['qrCodeDataUrl'],
      hasActiveQr: json['hasActiveQr'] ?? false,
      connectedNumber: json['connectedNumber'],
      connectedPushname: json['connectedPushname'],
      activeTemplatesCount: json['activeTemplatesCount'] ?? 0,
      totalTemplatesCount: json['totalTemplatesCount'] ?? 0,
      initializationError: json['initializationError'],
    );
  }

  factory WhatsAppStatusData.initial() {
    return WhatsAppStatusData(
      success: true,
      status: 'DISCONNECTED',
      isConnected: false,
      isReady: false,
      hasActiveQr: false,
      activeTemplatesCount: 0,
      totalTemplatesCount: 0,
    );
  }
}

class WhatsAppTemplateData {
  final String id;
  String name;
  String description;
  bool enabled;
  final String category;
  final String trigger;
  String template;

  WhatsAppTemplateData({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.category,
    required this.trigger,
    required this.template,
  });

  factory WhatsAppTemplateData.fromJson(Map<String, dynamic> json) {
    return WhatsAppTemplateData(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      enabled: json['enabled'] ?? true,
      category: json['category'] ?? 'automated',
      trigger: json['trigger'] ?? 'manual',
      template: json['template'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'enabled': enabled,
    'category': category,
    'trigger': trigger,
    'template': template,
  };

  WhatsAppTemplateData copyWith({
    String? name,
    String? description,
    bool? enabled,
    String? template,
  }) {
    return WhatsAppTemplateData(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      category: category,
      trigger: trigger,
      template: template ?? this.template,
    );
  }
}

class WhatsAppLogItem {
  final String id;
  final String timestamp;
  final String recipientPhone;
  final String templateId;
  final String status;
  final String? errorMessage;
  final String messageText;

  WhatsAppLogItem({
    required this.id,
    required this.timestamp,
    required this.recipientPhone,
    required this.templateId,
    required this.status,
    this.errorMessage,
    required this.messageText,
  });

  factory WhatsAppLogItem.fromJson(Map<String, dynamic> json) {
    return WhatsAppLogItem(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? '',
      recipientPhone: json['recipientPhone'] ?? '',
      templateId: json['templateId'] ?? 'custom',
      status: json['status'] ?? 'SENT',
      errorMessage: json['errorMessage'],
      messageText: json['messageText'] ?? '',
    );
  }
}

class WhatsAppService {
  static String? _cachedBaseUrl;

  /// Default server URL resolution:
  /// - Android emulator uses 10.0.2.2:3001
  /// - Web / Desktop uses localhost:3001
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:3001';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:3001';
    } catch (_) {}
    return 'http://localhost:3001';
  }

  static String get baseUrl => _cachedBaseUrl ?? defaultBaseUrl;

  static Future<void> loadBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('whatsapp_server_url');
      if (saved != null && saved.trim().isNotEmpty) {
        _cachedBaseUrl = saved.trim();
      }
    } catch (_) {}
  }

  static Future<void> setBaseUrl(String url) async {
    _cachedBaseUrl = url.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('whatsapp_server_url', url.trim());
    } catch (_) {}
  }

  /// Get status of WhatsApp client
  static Future<WhatsAppStatusData> getStatus() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/status');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return WhatsAppStatusData.fromJson(data);
      }
      return WhatsAppStatusData(
        success: false,
        status: 'DISCONNECTED',
        isConnected: false,
        isReady: false,
        hasActiveQr: false,
        activeTemplatesCount: 0,
        totalTemplatesCount: 0,
        initializationError: 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return WhatsAppStatusData(
        success: false,
        status: 'DISCONNECTED',
        isConnected: false,
        isReady: false,
        hasActiveQr: false,
        activeTemplatesCount: 0,
        totalTemplatesCount: 0,
        initializationError: e.toString(),
      );
    }
  }

  /// Trigger initialization / QR generation
  static Future<bool> connect() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/connect');
      final res = await http.post(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Disconnect / logout session
  static Future<bool> disconnect() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/disconnect');
      final res = await http.post(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Get all 4 templates
  static Future<Map<String, WhatsAppTemplateData>> getTemplates() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/templates');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawMap = data['templates'] as Map<String, dynamic>? ?? {};
        final Map<String, WhatsAppTemplateData> result = {};
        rawMap.forEach((key, val) {
          result[key] = WhatsAppTemplateData.fromJson(val);
        });
        return result;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Update a single template
  static Future<bool> updateTemplate(WhatsAppTemplateData template) async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/templates/${template.id}');
      final res = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': template.name,
          'description': template.description,
          'enabled': template.enabled,
          'template': template.template,
        }),
      ).timeout(const Duration(seconds: 6));
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Reset all templates to defaults
  static Future<bool> resetTemplates() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/templates/reset');
      final res = await http.post(uri).timeout(const Duration(seconds: 6));
      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Preview template text with variables
  static Future<String?> previewTemplate(
    String templateId, {
    String? templateString,
    Map<String, String>? context,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/preview');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'templateId': templateId,
          'templateString': templateString,
          'variables': context,
        }),
      ).timeout(const Duration(seconds: 6));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        return data['preview'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Send test message
  static Future<Map<String, dynamic>> sendTestMessage({
    required String recipientPhone,
    String? templateId,
    String? customMessage,
    Map<String, String>? context,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/send');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'recipientPhone': recipientPhone,
          'templateId': templateId,
          'customMessage': customMessage,
          'variables': context,
          'bypassDuplicateCheck': true,
        }),
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get delivery logs
  static Future<List<WhatsAppLogItem>> getLogs() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/logs');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['logs'] as List? ?? [];
        return list.map((e) => WhatsAppLogItem.fromJson(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

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
