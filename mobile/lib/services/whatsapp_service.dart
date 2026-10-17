import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend_config.dart';
import 'supabase_service.dart';

class WhatsAppStatusData {
  final bool success;
  final String
  status; // 'DISCONNECTED' | 'INITIALIZING' | 'QR_READY' | 'CONNECTED'
  final bool isConnected;
  final bool isReady;
  final String? qrCodeDataUrl;
  final bool hasActiveQr;
  final String? connectedNumber;
  final String? connectedPushname;
  final int activeTemplatesCount;
  final int totalTemplatesCount;
  final String? initializationError;
  final String? errorCode;

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
    this.errorCode,
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
      errorCode: json['code'],
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
  final bool delivered;
  final bool selfSend;
  final String? deliveryStatus;

  WhatsAppLogItem({
    required this.id,
    required this.timestamp,
    required this.recipientPhone,
    required this.templateId,
    required this.status,
    this.errorMessage,
    required this.messageText,
    this.delivered = false,
    this.selfSend = false,
    this.deliveryStatus,
  });

  factory WhatsAppLogItem.fromJson(Map<String, dynamic> json) {
    return WhatsAppLogItem(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? '',
      recipientPhone: json['recipientPhone'] ?? '',
      templateId: json['templateId'] ?? 'custom',
      status: json['status'] ?? 'UNKNOWN',
      errorMessage: json['errorMessage'] ?? json['error'],
      messageText: json['messageText'] ?? json['preview'] ?? '',
      delivered: json['delivered'] == true,
      selfSend: json['selfSend'] == true,
      deliveryStatus: json['deliveryStatus'],
    );
  }
}

class WhatsAppService {
  static const String productionBackendUrl = BackendConfig.productionUrl;
  static const String? customBackendUrl = null;

  static String? _cachedBaseUrl;
  static const _baseUrlPreferenceKey = 'whatsapp_server_url';

  static String get defaultBaseUrl {
    return BackendConfig.baseUrl;
  }

  static String get baseUrl {
    if (!BackendConfig.isRelease) return BackendConfig.baseUrl;
    if (customBackendUrl != null && customBackendUrl!.trim().isNotEmpty) {
      return customBackendUrl!.trim();
    }
    return _cachedBaseUrl ?? defaultBaseUrl;
  }

  static Future<Map<String, String>> _requestHeaders({
    bool json = false,
  }) async {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    final client = SupabaseConfig.client;
    var session = client?.auth.currentSession;
    final expiresAt = session?.expiresAt;
    if (client != null &&
        session != null &&
        expiresAt != null &&
        expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60) {
      try {
        session = (await client.auth.refreshSession()).session ??
            client.auth.currentSession;
      } catch (error) {
        debugPrint('[WhatsAppService] Could not refresh EaseInn session: $error');
      }
    }
    final accessToken = session?.accessToken;
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    return headers;
  }

  static Future<void> loadBaseUrl() async {
    // Debug runs always follow BackendConfig so an old saved Render URL cannot
    // silently send local testing traffic to production.
    if (!BackendConfig.isRelease) {
      _cachedBaseUrl = null;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('whatsapp_server_url');
      if (saved != null && saved.trim().isNotEmpty) {
        String clean = saved.trim();
        if (clean.contains('localhost') ||
            clean.contains('127.0.0.1') ||
            clean.contains('10.0.2.2')) {
          await prefs.remove(_baseUrlPreferenceKey);
          _cachedBaseUrl = null;
          return;
        }
        _cachedBaseUrl = clean;
      }
    } catch (_) {}
  }

  static Future<void> setBaseUrl(String url) async {
    final clean = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (clean.isEmpty || Uri.tryParse(clean)?.hasAuthority != true) return;
    _cachedBaseUrl = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_baseUrlPreferenceKey, clean);
    } catch (_) {}
  }

  /// Get status of WhatsApp client
  static Future<WhatsAppStatusData> getStatus() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/status');
      final res = await http
          .get(uri, headers: await _requestHeaders())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return WhatsAppStatusData.fromJson(data);
      }
      String? serverError;
      String? serverErrorCode;
      try {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic>) {
          serverError =
              body['error']?.toString() ?? body['message']?.toString();
          serverErrorCode = body['code']?.toString();
        }
      } catch (_) {}
      return WhatsAppStatusData(
        success: false,
        status: 'DISCONNECTED',
        isConnected: false,
        isReady: false,
        hasActiveQr: false,
        activeTemplatesCount: 0,
        totalTemplatesCount: 0,
        initializationError:
            serverError ?? 'Backend returned HTTP ${res.statusCode}',
        errorCode: serverErrorCode,
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
      final res = await http
          .post(uri, headers: await _requestHeaders())
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);
      _lastConnectError = res.statusCode >= 400
          ? (data is Map<String, dynamic>
                ? (data['error']?.toString() ??
                      'Backend returned HTTP ${res.statusCode}')
                : 'Backend returned HTTP ${res.statusCode}')
          : null;
      return data['success'] == true;
    } catch (error) {
      _lastConnectError = error.toString();
      return false;
    }
  }

  static String? _lastConnectError;
  static String? get lastConnectError => _lastConnectError;

  /// Disconnect / logout session
  static Future<bool> disconnect() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/disconnect');
      final res = await http
          .post(uri, headers: await _requestHeaders())
          .timeout(const Duration(seconds: 12));
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
      final res = await http
          .get(uri, headers: await _requestHeaders())
          .timeout(const Duration(seconds: 12));
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
      final res = await http
          .put(
            uri,
            headers: await _requestHeaders(json: true),
            body: jsonEncode({
              'name': template.name,
              'description': template.description,
              'enabled': template.enabled,
              'template': template.template,
            }),
          )
          .timeout(const Duration(seconds: 6));
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
      final res = await http
          .post(uri, headers: await _requestHeaders())
          .timeout(const Duration(seconds: 12));
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
      final res = await http
          .post(
            uri,
            headers: await _requestHeaders(json: true),
            body: jsonEncode({
              'templateId': templateId,
              'templateString': templateString,
              'variables': context,
            }),
          )
          .timeout(const Duration(seconds: 6));
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
      final res = await http
          .post(
            uri,
            headers: await _requestHeaders(json: true),
            body: jsonEncode({
              'recipientPhone': recipientPhone,
              'templateId': templateId,
              'customMessage': customMessage,
              'variables': context,
              'bypassDuplicateCheck': true,
            }),
          )
          .timeout(const Duration(seconds: 110));
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        if (res.statusCode >= 400 && data['error'] == null) {
          data['error'] = 'WhatsApp request failed (${res.statusCode}).';
        }
        if (data['success'] == true && data['accepted'] != true) {
          return {
            ...data,
            'success': false,
            'error': 'WhatsApp did not confirm acceptance of the message.',
          };
        }
        return data;
      }
      return {
        'success': false,
        'error': 'Unexpected WhatsApp server response.',
      };
    } catch (e) {
      if (e is TimeoutException) {
        return {
          'success': false,
          'accepted': false,
          'outcomeUnknown': true,
          'code': 'SEND_OUTCOME_UNKNOWN',
          'error':
              'The send timed out. Check WhatsApp and the delivery log before retrying to avoid a duplicate.',
        };
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get delivery logs
  static Future<List<WhatsAppLogItem>> getLogs() async {
    try {
      final uri = Uri.parse('$baseUrl/api/whatsapp/logs');
      final res = await http
          .get(uri, headers: await _requestHeaders())
          .timeout(const Duration(seconds: 12));
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
      final res = await http
          .post(
            uri,
            headers: await _requestHeaders(json: true),
            body: jsonEncode({
              'guestName': guestName,
              'phone': phone,
              'hotelName': hotelName,
              'roomNumber': roomNumber,
              'checkInDate': checkInDate,
              'checkOutDate': checkOutDate,
              'stayId': stayId,
            }),
          )
          .timeout(const Duration(seconds: 110));

      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint(
        '[WhatsAppService] Error triggering check-in notification: $e',
      );
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
      final res = await http
          .post(
            uri,
            headers: await _requestHeaders(json: true),
            body: jsonEncode({
              'guestName': guestName,
              'phone': phone,
              'hotelName': hotelName,
              'roomNumber': roomNumber,
              'checkInDate': checkInDate,
              'checkOutDate': checkOutDate,
              'stayId': stayId,
            }),
          )
          .timeout(const Duration(seconds: 110));

      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint(
        '[WhatsAppService] Error triggering check-out notification: $e',
      );
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
      final res = await http
          .post(
            uri,
            headers: await _requestHeaders(json: true),
            body: jsonEncode({
              'guestName': guestName,
              'phone': phone,
              'hotelName': hotelName,
              'roomNumber': roomNumber,
              'checkInDate': checkInDate,
              'checkOutDate': checkOutDate,
              'stayId': stayId,
            }),
          )
          .timeout(const Duration(seconds: 110));

      final data = jsonDecode(res.body);
      return data['success'] == true;
    } catch (e) {
      debugPrint(
        '[WhatsAppService] Error triggering reservation notification: $e',
      );
      return false;
    }
  }
}
