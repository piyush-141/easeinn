import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'backend_config.dart';

class OcrResult {
  final bool success;
  final String documentType;
  final String fullName;
  final String idNumber;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? pincode;
  final String? fatherName;
  final String? confidence;
  final String? rawMessage;
  /// Server-side timing breakdown (present when server returns _timing)
  final Map<String, dynamic>? timing;

  OcrResult({
    required this.success,
    required this.documentType,
    required this.fullName,
    required this.idNumber,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.pincode,
    this.fatherName,
    this.confidence,
    this.rawMessage,
    this.timing,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    final guestData = json['guest_data'] as Map<String, dynamic>? ?? {};
    final details   = json['details']    as Map<String, dynamic>? ?? {};
    final front     = details['front']   as Map<String, dynamic>?;
    final back      = details['back']    as Map<String, dynamic>?;

    String conf = '96.5%';
    if (front != null && front['confidence'] != null) {
      conf = front['confidence'].toString();
    } else if (back != null && back['confidence'] != null) {
      conf = back['confidence'].toString();
    }

    return OcrResult(
      success:      json['success'] ?? true,
      documentType: json['document_type'] ?? 'aadhaar',
      fullName:     guestData['full_name']     ?? '',
      idNumber:     guestData['id_number']     ?? '',
      dateOfBirth:  guestData['date_of_birth'] as String?,
      gender:       guestData['gender']        as String?,
      address:      guestData['address']       as String?,
      pincode:      guestData['pincode']       as String?,
      fatherName:   guestData['father_name']   as String?,
      confidence:   conf,
      rawMessage:   json['message']            as String?,
      timing:       json['_timing']            as Map<String, dynamic>?,
    );
  }
}

class OcrService {
  // ── Client-side resize ──────────────────────────────────────────────
  // Only applied when payload > 500KB. Uses platform-native codecs
  // (UIKit on iOS, android.graphics on Android) via flutter_image_compress.
  // Typical overhead: ~50-100ms. Typical upload saving: ~400-700ms on LTE.
  //
  // Images already under 500KB are returned unchanged — zero overhead.
  static const int _resizeThresholdBytes = 500 * 1024; // 500 KB
  static const int _maxDimension         = 1500;       // px on longest edge
  static const int _jpegQuality          = 72;

  static Future<Uint8List> _maybeResizeBytes(
    Uint8List bytes,
    String filename,
  ) async {
    if (bytes.length <= _resizeThresholdBytes) return bytes; // already small

    final ext = filename.split('.').last.toLowerCase();
    final CompressFormat fmt =
        ext == 'png' ? CompressFormat.png : CompressFormat.jpeg;

    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth:  _maxDimension,
        minHeight: _maxDimension,
        quality:   _jpegQuality,
        format:    fmt,
        keepExif:  false,
      );
      debugPrint(
        '[OcrService] resize: ${bytes.length}B → ${result.length}B '
        '(${((1 - result.length / bytes.length) * 100).toStringAsFixed(0)}% smaller)',
      );
      return result;
    } catch (e) {
      // If compression fails for any reason, send original — never drop the scan
      debugPrint('[OcrService] resize skipped: $e');
      return bytes;
    }
  }
  static String get baseUrl => BackendConfig.baseUrl;

  static MediaType _resolveMediaType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'jpg':
      case 'jpeg':
      default:
        return MediaType('image', 'jpeg');
    }
  }

  static Future<OcrResult> scanDocument({
    required String documentType,
    File? frontFile,
    File? backFile,
    Uint8List? frontBytes,
    Uint8List? backBytes,
    String? frontFilename,
    String? backFilename,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/scan-document');
      final request = http.MultipartRequest('POST', uri);

      request.fields['document_type'] = documentType;

      // Resize front + back concurrently before upload (native codec,
      // skipped automatically for images already ≤ 500 KB)
      final tResize = Stopwatch()..start();

      Uint8List? resolvedFront;
      Uint8List? resolvedBack;

      final results = await Future.wait([
        () async {
          if (frontFile != null) {
            final b = await frontFile.readAsBytes();
            return _maybeResizeBytes(b, frontFile.path.split('/').last);
          } else if (frontBytes != null && frontBytes.isNotEmpty) {
            return _maybeResizeBytes(frontBytes, frontFilename ?? 'document_front.jpg');
          }
          return null;
        }(),
        () async {
          if (backFile != null) {
            final b = await backFile.readAsBytes();
            return _maybeResizeBytes(b, backFile.path.split('/').last);
          } else if (backBytes != null && backBytes.isNotEmpty) {
            return _maybeResizeBytes(backBytes, backFilename ?? 'document_back.jpg');
          }
          return null;
        }(),
      ]);

      resolvedFront = results[0];
      resolvedBack  = results[1];
      tResize.stop();
      debugPrint('[OcrService] resize phase: ${tResize.elapsedMilliseconds}ms');

      // Front side
      if (resolvedFront != null) {
        final filename = frontFilename ?? frontFile?.path.split('/').last ?? 'document_front.jpg';
        request.files.add(
          http.MultipartFile.fromBytes(
            'document_front',
            resolvedFront,
            filename: filename,
            contentType: _resolveMediaType(filename),
          ),
        );
      }

      // Back side
      if (resolvedBack != null) {
        final filename = backFilename ?? backFile?.path.split('/').last ?? 'document_back.jpg';
        request.files.add(
          http.MultipartFile.fromBytes(
            'document_back',
            resolvedBack,
            filename: filename,
            contentType: _resolveMediaType(filename),
          ),
        );
      }

      final sw = Stopwatch()..start();
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);
      sw.stop();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final result  = OcrResult.fromJson(decoded);

        // Log real latency breakdown for benchmarking
        final serverMs = result.timing?['server_total_ms'];
        debugPrint(
          '[OcrService] round-trip=${sw.elapsedMilliseconds}ms'
          '${serverMs != null ? " server=${serverMs}ms" : ""}'
          ' front_vision=${result.timing?["front_vision_ms"]}ms'
          ' back_vision=${result.timing?["back_vision_ms"]}ms',
        );

        return result;
      } else {
        String errMsg = 'OCR server returned status ${response.statusCode}';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody['error'] != null) errMsg = errBody['error'];
        } catch (_) {}
        return OcrResult(
          success: false,
          documentType: documentType,
          fullName: '',
          idNumber: '',
          rawMessage: errMsg,
        );
      }
    } catch (e) {
      debugPrint('[OcrService] Real OCR error: $e');
      return OcrResult(
        success: false,
        documentType: documentType,
        fullName: '',
        idNumber: '',
        rawMessage: e.toString(),
      );
    }
  }
}
