import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStoreService {
  static const String _prefsPrefix = 'easeinn_local_cache_';

  static Future<File?> _getLocalFile(String propertyId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sanitized = propertyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      return File('${dir.path}/easeinn_store_$sanitized.json');
    } catch (e) {
      debugPrint('[LocalStoreService] Could not get doc directory: $e');
      return null;
    }
  }

  /// Save entire hotel state to local disk JSON & SharedPreferences cache
  static Future<bool> saveHotelData(String propertyId, Map<String, dynamic> data) async {
    final sanitizedId = propertyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final jsonStr = jsonEncode(data);

    bool fileSaved = false;
    try {
      final file = await _getLocalFile(sanitizedId);
      if (file != null) {
        await file.writeAsString(jsonStr, flush: true);
        fileSaved = true;
      }
    } catch (e) {
      debugPrint('[LocalStoreService] File write notice: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$sanitizedId', jsonStr);
      await prefs.setInt('easeinn_last_saved_$sanitizedId', DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (e) {
      debugPrint('[LocalStoreService] SharedPreferences write notice: $e');
      return fileSaved;
    }
  }

  /// Load hotel state from local disk JSON or SharedPreferences
  static Future<Map<String, dynamic>?> loadHotelData(String propertyId) async {
    final sanitizedId = propertyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    // 1. Try reading from File
    try {
      final file = await _getLocalFile(sanitizedId);
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalStoreService] File read notice: $e');
    }

    // 2. Fallback to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString('$_prefsPrefix$sanitizedId');
      if (content != null && content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('[LocalStoreService] SharedPreferences read notice: $e');
    }

    return null;
  }

  /// Clear local data for a property (e.g. on clean logout or reset)
  static Future<void> clearHotelData(String propertyId) async {
    final sanitizedId = propertyId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    try {
      final file = await _getLocalFile(sanitizedId);
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsPrefix$sanitizedId');
      await prefs.remove('easeinn_last_saved_$sanitizedId');
    } catch (_) {}
  }
}
